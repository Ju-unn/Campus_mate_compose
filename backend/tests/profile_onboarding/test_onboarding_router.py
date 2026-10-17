import asyncio
import logging
import base64
import json
from collections.abc import Callable
from datetime import datetime
from types import SimpleNamespace
from unittest.mock import AsyncMock
from uuid import UUID

import httpx
import pytest
from fastapi.testclient import TestClient

import app.profile_onboarding.router as router_module
from google.cloud import vision

from app.core import deps, errors
from app.core.deps import get_client, get_settings, get_vision_client
from app.core.time import SEOUL
from app.main import app
from app.settings import Settings
from app.signup_policy import bytea_literal, hash_phone
from private_columns import plaintext_gone

PROFILE_ID = UUID("11111111-1111-1111-1111-111111111111")
AUTH_HEADERS = {"Authorization": "Bearer valid-token"}
# student_id_content_type 이 매직바이트로 PNG 라고 인정하는 최소 바이트열.
_PNG_BYTES = b"\x89PNG\r\n\x1a\n" + b"0" * 32


@pytest.fixture(autouse=True)
def overrides():
    app.dependency_overrides[get_settings] = lambda: Settings(
            supabase_url="https://x.supabase.co",
            supabase_service_role_key="service-key",
            auth_hook_signing_secret="whsec_test",
            discord_webhook_url="https://discord.com/api/webhooks/test",
            google_cloud_project="campus-mate-test",
            openai_api_key="sk-test",
            phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test",
            avatar_tasks_queue="avatar-generate",
            avatar_worker_url="https://api.example.com/tasks/avatar-generate",
            avatar_tasks_service_account="tasks@campus-mate-test.iam.gserviceaccount.com",
    )
    # 저장 엔드포인트마다 매칭 벡터를 즉시 다시 만든다(조각 3) — 실제 OpenAI 를 부르지 않게 목을 끼운다.
    openai_client = AsyncMock()
    openai_client.embeddings.create.return_value = SimpleNamespace(
        data=[SimpleNamespace(embedding=[0.1] * 512), SimpleNamespace(embedding=[0.2] * 512)]
    )
    app.dependency_overrides[router_module.get_openai] = lambda: openai_client
    yield
    app.dependency_overrides.clear()
    # _wire 는 with 없이 TestClient 를 만들어 요청마다 루프가 새로 뜬다 —
    # 캐시에 남은 클라이언트는 이미 닫힌 루프에 묶인 채널을 들고 다음 테스트로 새어난다.
    deps._vision_client.cache_clear()


def _wire(
    handler: Callable[[httpx.Request], httpx.Response],
    verification: str = "verified",
    department: str | None = "컴퓨터공학과",
) -> TestClient:
    def wrapped(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/auth/v1/user" in url:
            return httpx.Response(200, json={"id": str(PROFILE_ID)})
        # 학생 인증 관문(get_verified_user_id)이 보는 조회. 기본은 인증도 학과 입력도 끝낸 사용자다.
        if "student_verification" in url and request.method == "GET":
            return httpx.Response(200, json=[{"student_verification": verification, "department": department, "school_email_verified_at": "2026-10-01T00:00:00+00:00"}])
        return handler(request)

    app.dependency_overrides[get_client] = lambda: httpx.AsyncClient(transport=httpx.MockTransport(wrapped))
    return TestClient(app)


def _vision(adult: int = 1, text: str = "") -> AsyncMock:
    # spec 없는 목은 비동기 클라이언트에 없는 메서드까지 받아 준다 — 그래서 500 이 테스트를 빠져나갔다.
    vision_client = AsyncMock(spec=vision.ImageAnnotatorAsyncClient)
    vision_client.batch_annotate_images.return_value = SimpleNamespace(
        responses=[
            SimpleNamespace(
                error=SimpleNamespace(message=""),
                safe_search_annotation=SimpleNamespace(adult=adult, violence=1),
                text_annotations=[SimpleNamespace(description=text)] if text else [],
                label_annotations=[],
            )
        ]
    )
    return vision_client


def _safe_vision() -> AsyncMock:
    return _vision()


def test_basic_info_rejects_duplicate_nickname_with_409():
    def handler(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/profiles" in str(request.url) and request.method == "PATCH":
            return httpx.Response(409, json={"message": "duplicate key"})
        return httpx.Response(200, json=[])

    client = _wire(handler)
    response = client.post(
        "/profile-onboarding/basic-info",
        headers=AUTH_HEADERS,
        json={
            "nickname": "가나", "birth_year": 2002, "height_cm": 170,
            "phone_number": "01001352468", "gender": "male",
        },
    )

    assert response.status_code == 409
    assert "닉네임" in response.json()["detail"]


def test_basic_info_creates_private_row_before_saving_phone():
    """set_phone_number 는 UPDATE 라 profile_private 행이 없으면 0행을 고치고 조용히 끝난다.
    학생증 단계를 거치지 않은 계정이면 행이 없어 전화번호가 안 남고 온보딩이 04-1 에 묶였다
    (2026-09-23 실기기 테스트). 행을 먼저 보장해야 한다."""
    calls: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/rest/v1/profile_private" in url and request.method == "POST":
            calls.append("ensure_private_row")
            assert request.headers["Prefer"] == "resolution=ignore-duplicates"
            assert json.loads(request.content) == {"profile_id": str(PROFILE_ID)}
            return httpx.Response(201)
        if "/rest/v1/rpc/set_phone_number" in url:
            calls.append("set_phone_number")
        return httpx.Response(200, json=[])

    response = _wire(handler).post(
        "/profile-onboarding/basic-info",
        headers=AUTH_HEADERS,
        json={
            "nickname": "가나", "birth_year": 2002, "height_cm": 170,
            "phone_number": "01001352468", "gender": "male",
        },
    )

    assert response.status_code == 200
    assert calls == ["ensure_private_row", "set_phone_number"]


def test_basic_info_saves_the_phone_number_in_e164():
    """앱은 하이픈을 붙여 보내도 저장은 한 모양이어야 한다 —
    조각 6 지인 차단이 E.164 로 정규화한 값에 HMAC 을 뜨기 때문이다(2026-09-24 대장 결정)."""
    sent: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/rpc/set_phone_number" in str(request.url):
            sent.append(json.loads(request.content))
        return httpx.Response(200, json=[])

    response = _wire(handler).post(
        "/profile-onboarding/basic-info",
        headers=AUTH_HEADERS,
        json={
            "nickname": "가나", "birth_year": 2002, "height_cm": 170,
            "phone_number": "010-0135-2468", "gender": "male",
        },
    )

    assert response.status_code == 200
    assert sent[0]["p_phone"] == "+821001352468"
    # 지인 차단 해시도 같은 E.164 값에서, 설정의 신원 키로 뜬다(조각 6 B4).
    assert sent[0]["p_phone_hmac"] == bytea_literal(hash_phone("identity-key-test", "+821001352468"))


@pytest.mark.parametrize("phone_number", [
    "010-1",          # 덜 친 번호
    "011-123-4567",   # 옛 10자리 — 가입은 010 만
    "010-1234-5678",  # 한 줄 순서
    "010-0000-0000",  # 같은 숫자
    "010-1111-2222",  # 알려진 가짜
])
def test_basic_info_refuses_a_number_that_is_not_a_real_010_phone(phone_number):
    """여기가 신뢰 경계다 — 앱이 막지 못한 값(옛 앱 · 직접 호출)이 들어오면 아무것도 쓰지 않고 돌려보낸다.
    가짜 번호는 지인 차단을 비껴가고 같은 번호 검사(지인 리뷰 · 추천)를 엉뚱하게 건다(전화번호_인증 §2-3)."""
    writes: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if request.method in ("PATCH", "POST"):
            writes.append(str(request.url))
        return httpx.Response(200, json=[])

    response = _wire(handler).post(
        "/profile-onboarding/basic-info",
        headers=AUTH_HEADERS,
        json={
            "nickname": "가나", "birth_year": 2002, "height_cm": 170,
            "phone_number": phone_number, "gender": "male",
        },
    )

    assert response.status_code == 422
    assert response.json() == {"detail": "올바른 휴대폰 번호를 입력해 주세요", "code": "phone_number_invalid"}
    assert writes == []


@pytest.mark.parametrize("gender", ["other", "Male", ""])
def test_basic_info_takes_only_male_or_female_before_writing(gender):
    """DB enum gender 와 같은 두 값만 받는다 — DB 에 맡기면 프로필 PATCH 에서야 22P02 로 떨어진다."""
    writes: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if request.method in ("PATCH", "POST"):
            writes.append(str(request.url))
        return httpx.Response(200, json=[])

    response = _wire(handler).post(
        "/profile-onboarding/basic-info",
        headers=AUTH_HEADERS,
        json={
            "nickname": "가나", "birth_year": 2002, "height_cm": 170,
            "phone_number": "010-0135-2468", "gender": gender,
        },
    )

    assert response.status_code == 422
    assert writes == []


def test_nickname_availability_ignores_callers_own_nickname():
    """04-1 을 다시 채울 때 방금 저장된 자기 닉네임이 '이미 있는 닉네임' 으로 막히면 안 된다."""
    seen_params: list[httpx.QueryParams] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/profiles" in str(request.url):
            seen_params.append(request.url.params)
        return httpx.Response(200, json=[])

    response = _wire(handler).get(
        "/profile-onboarding/nickname-availability", headers=AUTH_HEADERS, params={"nickname": "가나"}
    )

    assert response.json() == {"available": True}
    assert seen_params[0]["id"] == f"neq.{PROFILE_ID}"


def test_interests_rejects_fewer_than_three_tags_with_422():
    client = _wire(lambda request: httpx.Response(200, json=[]))
    response = client.post(
        "/profile-onboarding/interests",
        headers=AUTH_HEADERS,
        json={"tags": ["카페가기", "자전거"]},
    )

    assert response.status_code == 422
    assert "최소 3개" in response.json()["detail"]


def test_onboarding_rejects_unverified_student_with_403():
    client = _wire(lambda request: httpx.Response(200, json=[]), verification="pending")
    response = client.get("/profile-onboarding/next-step", headers=AUTH_HEADERS)

    assert response.status_code == 403
    assert "학생증" in response.json()["detail"]


def test_onboarding_rejects_missing_school_info_with_403():
    client = _wire(lambda request: httpx.Response(200, json=[]), department=None)
    response = client.get("/profile-onboarding/next-step", headers=AUTH_HEADERS)

    assert response.status_code == 403
    assert "학과" in response.json()["detail"]


def test_basic_info_rejects_under_nineteen_with_422():
    """가입 나이 자격은 Asia/Seoul 기준 올해 - birth_year >= 19 다(ERD.md). 경계값 19/18 을 같이 본다."""
    this_year = datetime.now(SEOUL).year
    body = {"nickname": "가나", "height_cm": 170, "phone_number": "01001352468", "gender": "male"}
    client = _wire(lambda request: httpx.Response(200, json=[]))

    just_old_enough = client.post(
        "/profile-onboarding/basic-info", headers=AUTH_HEADERS, json=body | {"birth_year": this_year - 19}
    )
    too_young = client.post(
        "/profile-onboarding/basic-info", headers=AUTH_HEADERS, json=body | {"birth_year": this_year - 18}
    )

    assert just_old_enough.status_code == 200
    assert too_young.status_code == 422
    # 문구는 "올해 − 19 년생부터"(사용자 결정 2026-09-29) — 앱 04-1 출생연도 칸 오류와 같다.
    assert f"{this_year - 19}년생부터 가입할 수 있어요" in json.dumps(too_young.json(), ensure_ascii=False)


def test_nickname_availability_rejects_ilike_wildcard_with_422():
    client = _wire(lambda request: httpx.Response(200, json=[]))
    response = client.get(
        "/profile-onboarding/nickname-availability", headers=AUTH_HEADERS, params={"nickname": "가%"}
    )

    assert response.status_code == 422


def test_interests_rejects_duplicate_tags_with_422():
    client = _wire(lambda request: httpx.Response(200, json=[]))
    response = client.post(
        "/profile-onboarding/interests",
        headers=AUTH_HEADERS,
        json={"tags": ["카페가기", "카페가기", "자전거"]},
    )

    assert response.status_code == 422
    assert "두 번" in response.json()["detail"]


def test_photo_upload_replaces_same_position_and_deletes_the_old_file():
    deleted_files: list[str] = []
    inserted: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/rest/v1/profile_photos" in url and request.method == "GET":
            return httpx.Response(200, json=[{"storage_path": "aa/old.png"}])
        if "/rest/v1/profile_photos" in url and request.method == "DELETE":
            return httpx.Response(204)
        if "/rest/v1/profile_photos" in url and request.method == "PATCH":
            return httpx.Response(204)
        if "/rest/v1/profile_photos" in url and request.method == "POST":
            inserted.append(json.loads(request.content))
            return httpx.Response(201, json=[])
        if "/storage/v1/object/profile-photos/" in url and request.method == "DELETE":
            deleted_files.append(url)
            return httpx.Response(200, json={})
        return httpx.Response(200, json={})

    app.dependency_overrides[get_vision_client] = _safe_vision
    client = _wire(handler)
    response = client.post(
        "/profile-onboarding/photos",
        headers=AUTH_HEADERS,
        files={"photo": ("a.png", _PNG_BYTES, "image/png")},
        data={"position": "0", "is_avatar_source": "true"},
    )

    assert response.status_code == 200
    assert len(inserted) == 1
    assert inserted[0]["is_avatar_source"] is True
    assert any("aa/old.png" in url for url in deleted_files)


def test_photo_upload_turns_unique_violation_into_409():
    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/rest/v1/profile_photos" in url and request.method == "GET":
            return httpx.Response(200, json=[])
        if "/rest/v1/profile_photos" in url and request.method == "POST":
            return httpx.Response(409, json={"code": "23505", "message": "duplicate key"})
        return httpx.Response(200, json={})

    app.dependency_overrides[get_vision_client] = _safe_vision
    client = _wire(handler)
    response = client.post(
        "/profile-onboarding/photos",
        headers=AUTH_HEADERS,
        files={"photo": ("a.png", _PNG_BYTES, "image/png")},
        data={"position": "0", "is_avatar_source": "false"},
    )

    assert response.status_code == 409


def _upload_photo_with(vision_client: AsyncMock, seen: list[httpx.Request]):
    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        if "/rest/v1/profile_photos" in str(request.url) and request.method == "GET":
            return httpx.Response(200, json=[])
        return httpx.Response(201, json=[])

    app.dependency_overrides[get_vision_client] = lambda: vision_client
    return _wire(handler).post(
        "/profile-onboarding/photos",
        headers=AUTH_HEADERS,
        files={"photo": ("a.png", _PNG_BYTES, "image/png")},
        data={"position": "0", "is_avatar_source": "true"},
    )


def _writes(seen: list[httpx.Request]) -> list[str]:
    # 가드(인증 · 학생 인증 조회)는 _wire 가 먼저 받아 seen 에 안 들어온다 — 남는 건 사진 저장 쪽 요청뿐이다.
    return [f"{r.method} {r.url.path}" for r in seen if r.method != "GET"]


def test_photo_upload_rejects_a_document_like_photo_and_saves_nothing(caplog):
    """학생증 · 신분증을 아바타 원본으로 올리면 아바타가 이상하게 나온다(사용자 결정 10-16 — 안내 + 서버 검사)."""
    seen: list[httpx.Request] = []
    with caplog.at_level("WARNING", logger="app.profile_onboarding.photos"):
        response = _upload_photo_with(_vision(text="학생증 홍길동 2024 컴퓨터공학과"), seen)

    assert response.status_code == 422
    assert response.json() == {"detail": errors.PHOTO_LOOKS_LIKE_DOCUMENT, "code": "photo_looks_like_document"}
    assert _writes(seen) == []
    # 거절 로그는 경로 이름만 — 프로필 id · 글자 원문은 없다.
    assert "verdict=document" in caplog.text and "source=onboarding" in caplog.text
    assert str(PROFILE_ID) not in caplog.text and "홍길동" not in caplog.text


def test_photo_upload_rejects_an_unsafe_photo_with_the_old_message():
    seen: list[httpx.Request] = []
    response = _upload_photo_with(_vision(adult=5), seen)

    assert response.status_code == 422
    assert response.json() == {"detail": "부적절한 사진은 올릴 수 없어요"}
    assert _writes(seen) == []


def test_photo_upload_lets_a_photo_with_short_text_through():
    seen: list[httpx.Request] = []
    response = _upload_photo_with(_vision(text="NIKE"), seen)

    assert response.status_code == 200
    assert any("/storage/v1/object/profile-photos/" in w for w in _writes(seen))


def test_photo_upload_builds_vision_client_on_the_event_loop_thread(monkeypatch):
    # 제공자가 sync 면 FastAPI 가 AnyIO 워커 스레드에서 부르고, 거기엔 루프가 없어
    # grpc aio 채널을 여는 순간 500 이 됐다(2026-09-25 운영 사진 업로드 장애).
    # 그래서 여기서는 일부러 get_vision_client 를 override 하지 않는다.
    # 목은 monkeypatch 앞에서 만든다 — 그래야 spec 이 가짜가 아닌 진짜 클래스를 가리킨다.
    safe_client = _safe_vision()

    def fake_client() -> AsyncMock:
        asyncio.get_running_loop()
        return safe_client

    monkeypatch.setattr(vision, "ImageAnnotatorAsyncClient", fake_client)

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/rest/v1/profile_photos" in url and request.method == "GET":
            return httpx.Response(200, json=[])
        if "/rest/v1/profile_photos" in url and request.method == "POST":
            return httpx.Response(201, json=[])
        return httpx.Response(200, json={})

    deps._vision_client.cache_clear()
    try:
        client = _wire(handler)
        response = client.post(
            "/profile-onboarding/photos",
            headers=AUTH_HEADERS,
            files={"photo": ("a.png", _PNG_BYTES, "image/png")},
            data={"position": "0", "is_avatar_source": "false"},
        )
    finally:
        # 가짜 클라이언트가 캐시에 남아 다음 테스트로 새어 나가지 않게.
        deps._vision_client.cache_clear()

    assert response.status_code == 200


def test_delete_photo_removes_row_and_storage_file():
    deleted_rows: list[str] = []
    deleted_files: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/rest/v1/profile_photos" in url and request.method == "GET":
            return httpx.Response(200, json=[{"storage_path": "aa/photo.png"}])
        if "/rest/v1/profile_photos" in url and request.method == "DELETE":
            deleted_rows.append(url)
            return httpx.Response(204)
        if "/storage/v1/object/profile-photos/" in url and request.method == "DELETE":
            deleted_files.append(url)
            return httpx.Response(200, json={})
        return httpx.Response(200, json={})

    client = _wire(handler)
    response = client.delete("/profile-onboarding/photos/2", headers=AUTH_HEADERS)

    assert response.status_code == 200
    assert any("position=eq.2" in url for url in deleted_rows)
    assert any("aa/photo.png" in url for url in deleted_files)


def test_delete_photo_returns_404_when_nothing_to_delete():
    client = _wire(lambda request: httpx.Response(200, json=[]))
    response = client.delete("/profile-onboarding/photos/2", headers=AUTH_HEADERS)

    assert response.status_code == 404


def test_avatar_generate_rejects_second_try_with_409():
    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/rest/v1/profile_avatars" in url and "status=eq.ready" in url:
            return httpx.Response(200, json=[{"id": "11111111-1111-1111-1111-11111111aaaa"}])
        return httpx.Response(200, json=[])

    client = _wire(handler)
    response = client.post("/profile-onboarding/avatar/generate", headers=AUTH_HEADERS)

    assert response.status_code == 409
    assert "한 번만" in response.json()["detail"]


def test_bio_draft_returns_the_saved_draft_without_calling_openai():
    openai_client = AsyncMock()
    app.dependency_overrides[router_module.get_openai] = lambda: openai_client
    client = _wire(lambda request: httpx.Response(200, json=[{"bio_draft": "저장해 둔 초안이에요"}]))
    response = client.post("/profile-onboarding/bio-draft", headers=AUTH_HEADERS)

    assert response.status_code == 200
    assert response.json()["draft"] == "저장해 둔 초안이에요"
    openai_client.chat.completions.create.assert_not_called()


def test_bio_draft_that_stays_empty_is_a_failure_and_is_not_saved():
    """OpenAI 가 두 번 다 빈 답(거부 등, content=None)이면 생성 실패와 같다 — 5xx 로 앱이 "직접 써 주세요" 를 띄우고,
    빈 초안을 저장하지 않아 다음에 열면 다시 만든다(빈 값을 저장하면 저장본이 있어 다시는 안 만든다)."""
    openai_client = AsyncMock()
    openai_client.chat.completions.create.return_value = SimpleNamespace(
        choices=[SimpleNamespace(message=SimpleNamespace(content=None))]
    )
    app.dependency_overrides[router_module.get_openai] = lambda: openai_client
    patches: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        path, select = request.url.path, request.url.params.get("select", "")
        if request.method == "PATCH":
            patches.append(json.loads(request.content))
            return httpx.Response(204)
        if path.endswith("/profiles") and select == "bio_draft":
            return httpx.Response(200, json=[{"bio_draft": None}])
        if path.endswith("/profiles"):
            return httpx.Response(200, json=[{
                "nickname": "하늘", "gender": "male", "mbti": None, "animal_type": "dog",
                "impression_type": "kind", "interest_tags": ["여행"], "my_traits": ["다정한"],
                "religion": "none", "is_smoker": False, "preferred_age_min": 20,
                "preferred_animal_types": ["cat"], "preferred_impression_types": ["chic"],
                "ideal_traits": [], "ideal_note": "", "bio": None, "status": "pending",
            }])
        return httpx.Response(200, json=[])

    response = _wire(handler).post("/profile-onboarding/bio-draft", headers=AUTH_HEADERS)

    assert response.status_code == 502
    assert openai_client.chat.completions.create.await_count == 2
    assert patches == []


def test_bio_draft_feeds_mbti_and_survey_in_korean_without_religion_or_smoking():
    """초안 재료는 MBTI · 설문 문장 한국어다 — 영어 코드값(religion=none)을 넘기지 않는다(2026-09-26 실기기 e).
    종교 · 흡연은 뺀다 — 민감정보이고 상세 화면 정보 칸에 이미 보인다(2026-10-15 대장 지시, GPT_소개글_프롬프트 §7-1 A)."""
    openai_client = AsyncMock()
    openai_client.chat.completions.create.return_value.choices = [SimpleNamespace(message=SimpleNamespace(content="초안"))]
    app.dependency_overrides[router_module.get_openai] = lambda: openai_client

    def handler(request: httpx.Request) -> httpx.Response:
        path, select = request.url.path, request.url.params.get("select", "")
        if request.method == "PATCH":
            return httpx.Response(204)
        if path.endswith("/profiles") and select == "bio_draft":
            return httpx.Response(200, json=[{"bio_draft": None}])
        if path.endswith("/profiles"):
            return httpx.Response(200, json=[{
                "nickname": "하늘", "gender": "male", "mbti": "ENFP", "animal_type": "dog",
                "impression_type": "kind", "interest_tags": ["여행"], "my_traits": ["다정한"],
                "religion": "none", "is_smoker": False, "preferred_age_min": 20,
                "preferred_animal_types": ["cat"], "preferred_impression_types": ["chic"],
                "ideal_traits": [], "ideal_note": "", "bio": None, "status": "pending",
            }])
        if path.endswith("/survey_answers"):
            return httpx.Response(200, json=[
                {"axis": 1, "value": 1}, {"axis": 2, "value": -0.5}, {"axis": 3, "value": 0},
            ])
        return httpx.Response(200, json=[])

    response = _wire(handler).post("/profile-onboarding/bio-draft", headers=AUTH_HEADERS)

    assert response.status_code == 200
    prompt = openai_client.chat.completions.create.call_args.kwargs["messages"][1]["content"]
    assert prompt.startswith("MBTI: ENFP\n성향: 밖이 좋아요, 낯을 많이 가려요\n")
    for left_out in ("religion=", "종교", "무교", "흡연"):
        assert left_out not in prompt, left_out


_NINE_ANSWERS = {str(axis): 0.5 for axis in range(1, 10)}


@pytest.mark.parametrize("body", [
    {"answers": _NINE_ANSWERS, "religion": "jedi", "is_smoker": False},
    {"answers": {**_NINE_ANSWERS, "1": 0.3}, "religion": "none", "is_smoker": False},
    {"answers": {**_NINE_ANSWERS, "10": 0.5}, "religion": "none", "is_smoker": False},
    {"answers": {k: v for k, v in _NINE_ANSWERS.items() if k != "9"}, "religion": "none", "is_smoker": False},
    {"answers": {}, "religion": "none", "is_smoker": False},
    {"answers": {**{k: v for k, v in _NINE_ANSWERS.items() if k != "9"}, "10": 0.5}, "religion": "none", "is_smoker": False},
])
def test_survey_rejects_bad_values_before_writing_anything(body):
    """E2E D-01: 없는 종교면 답 9행을 먼저 넣은 뒤 프로필 PATCH 가 22P02 로 실패해 답만 남았다.
    틀린 값은 쓰기 전에 막아 아무것도 남지 않는다 — 문구는 DB 가 막을 때와 같다."""
    writes = []

    def handler(request: httpx.Request) -> httpx.Response:
        if request.method != "GET":
            writes.append((request.method, request.url.path))
        return httpx.Response(201)

    response = _wire(handler).post("/profile-onboarding/survey", headers=AUTH_HEADERS, json=body)

    assert response.status_code == 422
    assert response.json() == {"detail": errors.INVALID_INPUT}
    assert writes == []


def test_survey_saves_every_allowed_value_and_religion():
    writes = []

    def handler(request: httpx.Request) -> httpx.Response:
        if request.method != "GET":
            writes.append((request.method, request.url.path, json.loads(request.content)))
        return httpx.Response(201)

    answers = {"1": -1, "2": -0.5, "3": 0, "4": 0.5, "5": 1, "6": 1, "7": 1, "8": 1, "9": 1}
    for religion in ("none", "protestant", "catholic", "buddhist"):
        response = _wire(handler).post(
            "/profile-onboarding/survey", headers=AUTH_HEADERS,
            json={"answers": answers, "religion": religion, "is_smoker": True},
        )
        assert response.status_code == 200, religion
    assert writes[0][1].endswith("/survey_answers") and len(writes[0][2]) == 9
    assert writes[1][2] == {"religion": "none", "is_smoker": True}


def test_ideal_note_rejects_blank_text():
    """필수 입력이다(2026-09-20 사용자 결정) — 공백만 쓴 글은 저장하지 않고 422 를 돌려준다."""
    patched: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/profiles" in str(request.url) and request.method == "PATCH":
            patched.append(json.loads(request.content))
        return httpx.Response(200, json=[])

    client = _wire(handler)
    response = client.post(
        "/profile-onboarding/ideal-note", headers=AUTH_HEADERS, json={"note": "   \n  "}
    )

    assert response.status_code == 422
    assert patched == []


def test_ideal_note_rejects_nine_characters():
    """최소 10자(2026-09-21 사용자 결정). 공백을 뗀 9자는 경계 바로 아래라 422 다."""
    patched: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/profiles" in str(request.url) and request.method == "PATCH":
            patched.append(json.loads(request.content))
        return httpx.Response(200, json=[])

    client = _wire(handler)
    response = client.post(
        "/profile-onboarding/ideal-note", headers=AUTH_HEADERS, json={"note": "  말이잘통하는사람요  "}
    )

    assert response.status_code == 422
    assert patched == []


def test_ideal_note_accepts_exactly_ten_characters():
    """경계 바로 위 10자는 저장한다 — 앞뒤 공백을 뗀 글이 그대로 들어간다."""
    patched: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/profiles" in str(request.url) and request.method == "PATCH":
            patched.append(json.loads(request.content))
        return httpx.Response(200, json=[])

    client = _wire(handler)
    response = client.post(
        "/profile-onboarding/ideal-note", headers=AUTH_HEADERS, json={"note": "  말 잘 통하는 사람  "}
    )

    assert response.status_code == 200
    assert patched[0]["ideal_note"] == "말 잘 통하는 사람"


# 자유 글 상한(2026-10-12 보안 점검 #11). 앱 입력칸에는 상한이 없어 넉넉하게 1000자 — 채팅 한 통과 같다.
@pytest.mark.parametrize(("path", "field"), [("/profile-onboarding/ideal-note", "note"), ("/profile-onboarding/bio", "bio")])
def test_free_text_over_a_thousand_characters_is_422_and_writes_nothing(path, field):
    patched: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/profiles" in str(request.url) and request.method == "PATCH":
            patched.append(json.loads(request.content))
        return httpx.Response(200, json=[])

    response = _wire(handler).post(path, headers=AUTH_HEADERS, json={field: "가" * 1001})

    assert response.status_code == 422
    assert patched == []


def test_ideal_note_accepts_a_thousand_characters():
    patched: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/profiles" in str(request.url) and request.method == "PATCH":
            patched.append(json.loads(request.content))
        return httpx.Response(200, json=[])

    response = _wire(handler).post("/profile-onboarding/ideal-note", headers=AUTH_HEADERS, json={"note": "가" * 1000})

    assert response.status_code == 200
    assert patched[0]["ideal_note"] == "가" * 1000


def test_ideal_note_line_endings_are_saved_as_newlines():
    patched: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/profiles" in str(request.url) and request.method == "PATCH":
            patched.append(json.loads(request.content))
        return httpx.Response(200, json=[])

    response = _wire(handler).post(
        "/profile-onboarding/ideal-note", headers=AUTH_HEADERS, json={"note": "말이 잘 통하는\r\n사람이 좋아요"}
    )

    assert response.status_code == 200
    assert patched[0]["ideal_note"] == "말이 잘 통하는\n사람이 좋아요"


@pytest.mark.parametrize(("path", "field"), [("/profile-onboarding/ideal-note", "note"), ("/profile-onboarding/bio", "bio")])
def test_free_text_with_forty_one_lines_is_422_and_writes_nothing(path, field):
    patched: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/profiles" in str(request.url) and request.method == "PATCH":
            patched.append(json.loads(request.content))
        return httpx.Response(200, json=[])

    response = _wire(handler).post(path, headers=AUTH_HEADERS, json={field: "\n".join(["가나다라마바사아자차"] * 41)})

    assert response.status_code == 422
    assert patched == []


def test_ideal_conditions_rejects_empty_face_or_impression_choice():
    """선호 얼굴상·인상도 각 1개 이상 필수다."""
    patched: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/profiles" in str(request.url) and request.method == "PATCH":
            patched.append(json.loads(request.content))
        return httpx.Response(200, json=[])

    client = _wire(handler)
    response = client.post(
        "/profile-onboarding/ideal-conditions",
        headers=AUTH_HEADERS,
        json={
            "preferred_age_min": 20, "preferred_age_max": 26,
            "preferred_animal_types": [], "preferred_impression_types": ["kind"],
        },
    )

    assert response.status_code == 422
    assert patched == []


def test_ideal_note_refreshes_matching_vectors():
    """저장 재료가 바뀌면 매칭 벡터를 즉시 다시 만든다(조각 3, 설계 §6.3)."""
    saved: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/rest/v1/profiles" in url and request.method == "GET":
            return httpx.Response(200, json=[{
                "major": "컴퓨터공학과", "mbti": "ENFP", "bio": "등산 좋아해요.",
                "ideal_note": "말 잘 통하는 사람이요.",
            }])
        if "/rest/v1/profile_vectors" in url and request.method == "POST":
            saved.append(json.loads(request.content))
            return httpx.Response(201, json=[])
        return httpx.Response(200, json=[])

    client = _wire(handler)
    response = client.post(
        "/profile-onboarding/ideal-note",
        headers=AUTH_HEADERS,
        json={"note": "말 잘 통하는 사람이요."},
    )

    assert response.status_code == 200
    assert len(saved) == 1
    assert len(saved[0]["self_embedding"]) == 512
    assert len(saved[0]["want_embedding"]) == 512


# --- 카카오톡 아이디 저장 · 진행도 (M2: 평문 열 없음 — 암호문 열만) -----------------------------------------------


def _post_kakao_id(client: TestClient, kakao_id: str = "fox_rain"):
    return client.post("/profile-onboarding/kakao-id", headers=AUTH_HEADERS, json={"kakao_id": kakao_id})


def _without_plaintext(handler: Callable[[httpx.Request], httpx.Response]):
    """평문 열이 없어진 profile_private 를 앞에 둔다 — 서버가 평문 열을 쓰면 42703."""
    return lambda request: plaintext_gone(request) or handler(request)


def test_kakao_id_is_written_only_through_the_encryption_rpc():
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json=[])

    response = _post_kakao_id(_wire(_without_plaintext(handler)))

    assert response.status_code == 200
    encrypted = [r for r in seen if "/rest/v1/rpc/set_kakao_id" in str(r.url)]
    assert [json.loads(r.content) for r in encrypted] == [
        {"p_profile": str(PROFILE_ID), "p_kakao_id": "fox_rain", "p_key": "phone-key-test"}
    ]
    assert "phone-key-test" not in str(encrypted[0].url)
    assert not [r for r in seen if r.method == "PATCH" and "/rest/v1/profile_private" in str(r.url)]


def test_kakao_id_creates_the_private_row_before_the_update_only_encrypted_write():
    """set_kakao_id 는 UPDATE 전용 — 행이 없으면 0행을 고치고 조용히 끝난다. 부르기 전에 행을 보장한다."""
    calls: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/rest/v1/profile_private" in url and request.method == "POST":
            calls.append("ensure_private_row")
        if "/rest/v1/rpc/set_kakao_id" in url:
            calls.append("set_kakao_id")
        return httpx.Response(200, json=[])

    assert _post_kakao_id(_wire(_without_plaintext(handler))).status_code == 200
    assert calls == ["ensure_private_row", "set_kakao_id"]


@pytest.mark.parametrize("failing", ["set_kakao_id", "ensure_private_row"])
@pytest.mark.parametrize("status", [404, 500])
def test_kakao_id_save_fails_when_the_encrypted_write_fails(failing, status, caplog):
    """암호문이 유일한 저장소다 — 실패를 삼키면 "저장됐어요" 뒤에 값이 없다. 요청을 실패시킨다."""
    failed: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        is_rpc = "/rest/v1/rpc/set_kakao_id" in url
        is_ensure = "/rest/v1/profile_private" in url and request.method == "POST"
        if (failing == "set_kakao_id" and is_rpc) or (failing == "ensure_private_row" and is_ensure):
            failed.append(failing)
            return httpx.Response(status, json={"message": "boom"})
        return httpx.Response(200, json=[])

    _wire(_without_plaintext(handler))
    with caplog.at_level(logging.DEBUG):
        response = _post_kakao_id(TestClient(app, raise_server_exceptions=False), "secret_kakao")

    assert failed == [failing]  # 500 은 그 쓰기에서 났다(평문 열 같은 다른 이유가 아니다)
    assert response.status_code == 500
    assert "secret_kakao" not in caplog.text and "phone-key-test" not in caplog.text


def test_kakao_id_has_a_generous_upper_bound():
    client = _wire(_without_plaintext(lambda request: httpx.Response(200, json=[])))

    assert _post_kakao_id(client, "a" * 64).status_code == 200
    assert _post_kakao_id(client, "a" * 65).status_code == 422


def _next_step_handler(decrypted_kakao_id: str | None, decrypt_status: int = 200):
    from app.consents.policy import CONSENT_VERSION, REQUIRED_KINDS

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/rest/v1/user_consents" in url:
            return httpx.Response(200, json=[{"kind": k, "version": CONSENT_VERSION} for k in sorted(REQUIRED_KINDS)])
        if "/rest/v1/rpc/decrypt_profile_private" in url:
            if decrypt_status != 200:
                return httpx.Response(decrypt_status, json={"message": "boom"})
            return httpx.Response(200, json=[{"real_name": None, "kakao_id": decrypted_kakao_id}])
        if "/rest/v1/profile_private" in url:
            return httpx.Response(200, json=[{"phone_number": "\\x01"}])
        if "/rest/v1/profiles" in url:
            return httpx.Response(200, json=[{
                "nickname": "가나", "gender": "male", "mbti": None, "animal_type": None, "impression_type": None,
                "interest_tags": [], "my_traits": [], "religion": None, "is_smoker": None,
                "preferred_age_min": None, "preferred_animal_types": [], "preferred_impression_types": [],
                "ideal_traits": [], "ideal_note": None, "bio": None, "status": "pending",
            }])
        return httpx.Response(200, json=[])

    return _without_plaintext(handler)


def _next_step(handler):
    _wire(handler)
    return TestClient(app, raise_server_exceptions=False).get("/profile-onboarding/next-step", headers=AUTH_HEADERS)


def test_progress_counts_a_kakao_id_from_the_encrypted_column():
    assert _next_step(_next_step_handler(decrypted_kakao_id="fox_enc")).json()["step"] == "photos"


def test_progress_asks_for_the_kakao_id_when_the_encrypted_column_is_empty():
    assert _next_step(_next_step_handler(decrypted_kakao_id=None)).json()["step"] == "kakao_id"


def test_progress_fails_instead_of_asking_again_when_decrypt_fails():
    """복호화가 안 된다고 "카톡 아이디 미입력" 으로 보면 이미 낸 사람을 04-1b 로 돌려보낸다 — 요청을 실패시킨다."""
    seen: list[str] = []
    inner = _next_step_handler(None, decrypt_status=404)

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request.url.path)
        return inner(request)

    assert _next_step(handler).status_code == 500
    assert "/rest/v1/rpc/decrypt_profile_private" in seen  # 500 은 복호화에서 났다


# --- 가입 확정: 아바타 확인이 맨 끝(06-3 뒤)이 되어 06-3 저장 뒤에도 가입이 끝날 수 있다 (2026-10-17) ---------------


_DONE_PROFILE_ROW = {
    "nickname": "가나", "gender": "male", "mbti": "ENFP", "animal_type": "dog", "impression_type": "kind",
    "interest_tags": ["a", "b", "c"], "my_traits": ["a", "b", "c"], "religion": "none", "is_smoker": False,
    "preferred_age_min": 20, "preferred_animal_types": ["cat"], "preferred_impression_types": ["kind"],
    "ideal_traits": ["a", "b", "c"], "ideal_note": "말 잘 통하는 사람이요", "bio": "안녕하세요",
}


class _DoneWorld:
    """06-3 까지 다 낸 사람의 가짜 DB. 아바타 ready 행 유무와 프로필 상태를 시험이 바꾼다.
    상태를 바꾸는 PATCH 만 따로 모은다(자기소개 저장 PATCH 는 본문에 status 가 없다)."""

    def __init__(self, status: str = "pending", avatar_ready: bool = True):
        self.status, self.avatar_ready = status, avatar_ready
        self.activations: list[tuple[dict, dict]] = []

    def __call__(self, request: httpx.Request) -> httpx.Response:
        return plaintext_gone(request) or self._handle(request)

    def _handle(self, request: httpx.Request) -> httpx.Response:
        from app.consents.policy import CONSENT_VERSION, REQUIRED_KINDS

        path, params = request.url.path, request.url.params
        if request.method == "PATCH":
            body = json.loads(request.content)
            if path.endswith("/profiles") and "status" in body:
                self.activations.append((dict(params), body))
            return httpx.Response(204)
        if path.endswith("/user_consents"):
            return httpx.Response(200, json=[{"kind": k, "version": CONSENT_VERSION} for k in sorted(REQUIRED_KINDS)])
        if path.endswith("/rpc/decrypt_profile_private"):
            return httpx.Response(200, json=[{"real_name": None, "kakao_id": "fox_rain"}])
        if path.endswith("/profile_private"):
            return httpx.Response(200, json=[{"phone_number": "\\x01"}])
        if path.endswith("/profile_photos"):
            return httpx.Response(200, json=[{"is_avatar_source": True}, {"is_avatar_source": False}])
        if path.endswith("/profile_avatars") and params.get("status") == "eq.ready":
            return httpx.Response(200, json=[{"id": "a1"}] if self.avatar_ready else [])
        if path.endswith("/survey_answers"):
            return httpx.Response(200, json=[{"axis": axis, "value": 0.5} for axis in range(1, 10)])
        if path.endswith("/profiles") and request.method == "GET":
            return httpx.Response(200, json=[{**_DONE_PROFILE_ROW, "status": self.status}])
        return httpx.Response(200, json=[])


_ACTIVATION = ({"id": f"eq.{PROFILE_ID}", "status": "eq.pending"}, {"status": "active"})


def test_next_step_activates_a_pending_profile_when_everything_is_done():
    """06-3 저장 때 아바타가 아직이던 사람은 아바타가 생긴 뒤의 단계 조회가 가입을 끝낸다.
    pending 행만 고친다 — 정지 · 탈퇴를 되살리지 않고, 동시에 두 번 불려도 한 번만 바뀐다."""
    world = _DoneWorld(status="pending")

    response = _next_step(world)

    assert response.json()["step"] == "complete"
    assert world.activations == [_ACTIVATION]


@pytest.mark.parametrize("status", ["active", "suspended", "withdrawn"])
def test_next_step_does_not_write_for_a_profile_that_is_not_pending(status):
    """단계 조회는 토큰 갱신 때마다 돈다 — 이미 가입한 사람에게 매번 쓰지 않는다. 정지 · 탈퇴도 건드리지 않는다."""
    world = _DoneWorld(status=status)

    response = _next_step(world)

    assert response.json()["step"] == "complete"
    assert world.activations == []


def test_next_step_does_not_activate_while_the_avatar_is_not_ready():
    world = _DoneWorld(status="pending", avatar_ready=False)

    response = _next_step(world)

    assert response.json()["step"] == "avatar"
    assert world.activations == []


def _post_bio(world: _DoneWorld):
    return _wire(world).post("/profile-onboarding/bio", headers=AUTH_HEADERS, json={"bio": "안녕하세요"})


def test_bio_does_not_activate_while_the_avatar_is_not_ready():
    world = _DoneWorld(status="pending", avatar_ready=False)

    response = _post_bio(world)

    assert response.status_code == 200
    assert response.json() == {"ok": True}
    assert world.activations == []


def test_bio_activates_when_the_avatar_is_ready():
    """06-3 저장 때 아바타가 이미 있으면 그 자리에서 가입이 끝난다(종전과 같다). 조건부 쓰기 한 번."""
    world = _DoneWorld(status="pending", avatar_ready=True)

    response = _post_bio(world)

    assert response.json() == {"ok": True}
    assert world.activations == [_ACTIVATION]


def test_a_bio_saved_before_the_avatar_finishes_is_activated_by_a_later_next_step():
    """옛 앱(빌드 15 · 16 · vc8) + 새 서버: 06-3 저장 → 05-12 에서 기다림 → 완성 → "다음" 의 단계 조회로 가입이 끝난다.
    이 줄이 없으면 그 사람은 영영 pending 이라 카드 후보에 안 잡힌다."""
    world = _DoneWorld(status="pending", avatar_ready=False)

    assert _post_bio(world).json() == {"ok": True}
    assert _next_step(world).json()["step"] == "avatar"  # 옛 앱은 05-12 로 간다
    world.avatar_ready = True
    assert _next_step(world).json()["step"] == "complete"
    world.status = "active"  # 위 PATCH 가 바꾼 상태 — 다음 조회(토큰 갱신)는 쓰지 않는다
    assert _next_step(world).json()["step"] == "complete"

    assert world.activations == [_ACTIVATION]
