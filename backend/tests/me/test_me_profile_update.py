"""15c 자기소개 · 15-6 닉네임 · 키 저장 PATCH /me/profile(계획서 2-5)."""
import json
from datetime import datetime, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock

import httpx
import pytest

import app.profile_onboarding.router as onboarding_router
from tests.me.test_me_profile import AUTH_HEADERS, _wire, overrides  # noqa: F401 — autouse 픽스처
from app.core.deps import get_now
from app.core.time import SEOUL
from app.main import app

NOW = datetime(2026, 9, 28, 14, 0, tzinfo=SEOUL)
CURRENT = {"nickname": "하늘", "nickname_changed_at": "2026-08-01T00:00:00+09:00"}  # 58일 전 — 바꿀 수 있다
LOCKED = {"nickname": "하늘", "nickname_changed_at": "2026-09-20T00:00:00+09:00"}   # 8일 전 — 잠김


def _patch(
    body: dict, current: dict = CURRENT, seen: list | None = None,
    conflict: bool = False, patch_error_code: str | None = None,
) -> httpx.Response:
    """profiles GET(select=nickname,nickname_changed_at) → [current], profiles PATCH → 204(conflict 면 409 23505),
    profile_vectors POST → 201. seen 에 가드 뒤 요청을 쌓는다."""
    seen = [] if seen is None else seen

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        path, params = request.url.path, request.url.params
        # 같은 profiles 를 닉네임 조회와 벡터 재료 조회가 둘 다 읽는다 — select 키로 가른다.
        if request.method == "GET" and path.endswith("/profiles"):
            if params.get("select") == "nickname,nickname_changed_at":
                return httpx.Response(200, json=[current])
            return httpx.Response(200, json=[{"bio": "새 소개"}])
        if request.method == "GET" and path.endswith("/survey_answers"):
            return httpx.Response(200, json=[])
        if request.method == "PATCH" and path.endswith("/profiles"):
            if conflict:
                return httpx.Response(409, json={"code": "23505", "message": "duplicate key"})
            if patch_error_code:
                return httpx.Response(400, json={"code": patch_error_code, "message": "check"})
            return httpx.Response(204)
        if request.method == "POST" and path.endswith("/profile_vectors"):
            return httpx.Response(201)
        return httpx.Response(404, json={"message": f"unexpected {request.method} {request.url}"})

    openai_client = AsyncMock()
    openai_client.embeddings.create.return_value = SimpleNamespace(
        data=[SimpleNamespace(embedding=[0.1] * 512), SimpleNamespace(embedding=[0.2] * 512)]
    )
    app.dependency_overrides[onboarding_router.get_openai] = lambda: openai_client
    app.dependency_overrides[get_now] = lambda: NOW
    return _wire(handler).patch("/me/profile", headers=AUTH_HEADERS, json=body)


def _profile_patches(seen):
    return [json.loads(r.content) for r in seen if r.method == "PATCH" and r.url.path.endswith("/profiles")]


def _vector_saves(seen):
    return [r for r in seen if r.method == "POST" and r.url.path.endswith("/profile_vectors")]


def test_bio_is_trimmed_saved_and_refreshes_the_vectors():
    seen = []
    response = _patch({"bio": "  새 소개  "}, seen=seen)

    assert response.status_code == 200
    assert response.json() == {"ok": True}
    assert _profile_patches(seen) == [{"bio": "새 소개"}]
    assert len(_vector_saves(seen)) == 1


def test_blank_bio_is_422_and_writes_nothing():
    seen = []
    assert _patch({"bio": "   "}, seen=seen).status_code == 422
    assert _profile_patches(seen) == []


def test_an_empty_body_is_422():
    # 고칠 칸이 없는 요청은 앱 버그다 — 아무것도 안 쓰고 200 을 주면 숨는다.
    assert _patch({}).status_code == 422


@pytest.mark.parametrize("body", [{"nickname": None}, {"height_cm": None}, {"bio": None}])
def test_null_nickname_height_or_bio_is_422(body):
    # 앱은 null 을 보내지 않는다. 보내면 온보딩 완료 check 가 막아 뜻 모를 오류가 되니 앞에서 막는다(편차 S5 — 보낸 칸 전부).
    seen = []
    assert _patch(body, seen=seen).status_code == 422
    assert _profile_patches(seen) == []


def test_status_is_never_touched():
    seen = []
    _patch({"bio": "새 소개"}, seen=seen)
    assert _profile_patches(seen)
    assert all("status" not in body for body in _profile_patches(seen))


def test_new_nickname_saves_and_starts_the_thirty_days():
    seen = []
    assert _patch({"nickname": "바다"}, seen=seen).status_code == 200
    assert _profile_patches(seen) == [{"nickname": "바다", "nickname_changed_at": "now()"}]
    # 닉네임은 문장 재료가 아니다.
    assert _vector_saves(seen) == []


def test_same_nickname_does_not_restart_the_thirty_days():
    seen = []
    # 15-6 은 키만 고쳐도 닉네임을 같이 보낸다. 같으면 잠금 검사도 안 하고 쓰지도 않는다.
    assert _patch({"nickname": "하늘", "height_cm": 180}, current=LOCKED, seen=seen).status_code == 200
    assert _profile_patches(seen) == [{"height_cm": 180}]


def test_same_nickname_alone_writes_nothing():
    seen = []
    assert _patch({"nickname": "하늘"}, current=LOCKED, seen=seen).status_code == 200
    assert _profile_patches(seen) == []


def test_height_saves_while_the_nickname_is_locked():
    seen = []
    assert _patch({"height_cm": 175}, current=LOCKED, seen=seen).status_code == 200
    assert _profile_patches(seen) == [{"height_cm": 175}]
    # 키는 문장 재료가 아니다.
    assert _vector_saves(seen) == []


def test_changing_the_nickname_within_thirty_days_is_409():
    seen = []
    response = _patch({"nickname": "바다"}, current=LOCKED, seen=seen)
    assert response.status_code == 409
    assert response.json() == {"detail": "닉네임은 30일에 한 번 바꿀 수 있어요"}
    assert _profile_patches(seen) == []


def test_the_thirty_days_end_exactly_at_the_line():
    # 바꾼 지 정확히 30일이 된 순간부터 된다 — get_now 를 끼워 경계를 본다(벽시계 금지).
    at_line = {"nickname": "하늘", "nickname_changed_at": (NOW - timedelta(days=30)).isoformat()}
    assert _patch({"nickname": "바다"}, current=at_line).status_code == 200


def test_one_second_before_the_line_is_still_locked():
    almost = {"nickname": "하늘", "nickname_changed_at": (NOW - timedelta(days=30) + timedelta(seconds=1)).isoformat()}
    assert _patch({"nickname": "바다"}, current=almost).status_code == 409


def test_never_changed_nickname_can_change_now():
    assert _patch({"nickname": "바다"}, current={"nickname": "하늘", "nickname_changed_at": None}).status_code == 200


def test_taken_nickname_is_409():
    response = _patch({"nickname": "바다"}, conflict=True)
    assert response.status_code == 409
    assert response.json() == {"detail": "이미 있는 닉네임이에요"}


@pytest.mark.parametrize("nickname", ["a", "여섯글자닉네", "하늘!", "하 늘", "%_"])
def test_badly_formed_nickname_is_422(nickname):
    seen = []
    assert _patch({"nickname": nickname}, seen=seen).status_code == 422
    assert _profile_patches(seen) == []


def test_height_outside_the_db_range_is_422():
    # DB check(120~230)가 23514 로 막고 raise_for_status 가 422 로 바꾼다 — 가짜 PATCH 가 23514 로 답하게 한다.
    response = _patch({"height_cm": 300}, patch_error_code="23514")
    assert response.status_code == 422
    assert response.json() == {"detail": "입력한 값을 다시 확인해 주세요"}


def test_rejects_missing_login():
    assert _wire(lambda r: httpx.Response(404)).patch("/me/profile", json={"bio": "새 소개"}).status_code == 401


# ---- 기본 정보 수정 확대: MBTI · 종교 · 흡연 · 얼굴상 · 인상 (사용자 결정 2026-10-10) ----

@pytest.mark.parametrize("body", [
    {"mbti": "ENFP"}, {"mbti": "ISTJ"}, {"religion": "buddhist"}, {"religion": "none"},
    {"is_smoker": True}, {"is_smoker": False},
    {"animal_type": "hamster", "impression_type": "innocent"},
])
def test_new_fields_are_saved_as_sent(body):
    seen = []
    assert _patch(body, seen=seen).status_code == 200
    assert _profile_patches(seen) == [body]


@pytest.mark.parametrize("body", [
    {"mbti": "enfp"}, {"mbti": "ENF"}, {"mbti": "XXXX"}, {"mbti": "ENFPX"}, {"mbti": ""},
    {"religion": "islam"}, {"religion": ""}, {"religion": None},
    {"is_smoker": None}, {"is_smoker": "yes"},
    {"animal_type": "dragon", "impression_type": "kind"},
    {"animal_type": "dog", "impression_type": "scary"},
    {"animal_type": None, "impression_type": None},
])
def test_bad_values_for_the_new_fields_are_422_and_write_nothing(body):
    seen = []
    assert _patch(body, seen=seen).status_code == 422
    assert _profile_patches(seen) == []


@pytest.mark.parametrize("body", [{"animal_type": "dog"}, {"impression_type": "kind"}])
def test_animal_and_impression_come_as_a_pair(body):
    # 문장은 둘 다 있어야 만들어진다 — 한쪽만 바꾸면 반쪽 얼굴상이 남는다.
    seen = []
    assert _patch(body, seen=seen).status_code == 422
    assert _profile_patches(seen) == []


def test_nickname_lock_still_blocks_a_save_that_also_carries_new_fields():
    seen = []
    assert _patch({"nickname": "바다", "mbti": "INTJ"}, current=LOCKED, seen=seen).status_code == 409
    assert _profile_patches(seen) == []
