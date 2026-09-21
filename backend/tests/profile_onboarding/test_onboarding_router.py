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
from app.core.time import SEOUL
from app.main import app
from app.settings import Settings

PROFILE_ID = UUID("11111111-1111-1111-1111-111111111111")
AUTH_HEADERS = {"Authorization": "Bearer valid-token"}
# student_id_content_type 이 매직바이트로 PNG 라고 인정하는 최소 바이트열.
_PNG_BYTES = b"\x89PNG\r\n\x1a\n" + b"0" * 32


@pytest.fixture(autouse=True)
def overrides(monkeypatch):
    monkeypatch.setattr(
        router_module,
        "get_settings",
        lambda: Settings(
            supabase_url="https://x.supabase.co",
            supabase_service_role_key="service-key",
            auth_hook_signing_secret="whsec_test",
            discord_webhook_url="https://discord.com/api/webhooks/test",
            google_cloud_project="campus-mate-test",
            openai_api_key="sk-test",
            phone_encryption_key="phone-key-test",
        ),
    )
    # 저장 엔드포인트마다 매칭 벡터를 즉시 다시 만든다(조각 3) — 실제 OpenAI 를 부르지 않게 목을 끼운다.
    router_module._openai_client_override = AsyncMock()
    router_module._openai_client_override.embeddings.create.return_value = SimpleNamespace(
        data=[SimpleNamespace(embedding=[0.1] * 512), SimpleNamespace(embedding=[0.2] * 512)]
    )
    yield
    router_module._client_override = None
    router_module._openai_client_override = None
    router_module._vision_client_override = None


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
            return httpx.Response(200, json=[{"student_verification": verification, "department": department}])
        return handler(request)

    router_module._client_override = httpx.AsyncClient(transport=httpx.MockTransport(wrapped))
    return TestClient(app)


def _safe_vision() -> AsyncMock:
    vision_client = AsyncMock()
    annotation = vision_client.safe_search_detection.return_value.safe_search_annotation
    annotation.adult = 1
    annotation.violence = 1
    return vision_client


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
            "phone_number": "01012345678", "gender": "male",
        },
    )

    assert response.status_code == 409
    assert "닉네임" in response.json()["detail"]


def test_interests_rejects_fewer_than_three_tags_with_422():
    client = _wire(lambda request: httpx.Response(200, json=[]))
    response = client.post(
        "/profile-onboarding/interests",
        headers=AUTH_HEADERS,
        json={"tags": ["카페가기", "자전거"]},
    )

    assert response.status_code == 422
    assert "최소 3개" in response.json()["detail"]


def test_avatar_generate_grants_ten_hearts_on_fifth_consecutive_failure():
    hearts_requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/rest/v1/profile_photos" in url and request.method == "GET":
            return httpx.Response(200, json=[{"storage_path": "aa/source.png"}])
        if "/storage/v1/object/profile-photos/" in url and request.method == "GET":
            return httpx.Response(200, content=b"source-photo-bytes")
        if "/rest/v1/profile_avatars" in url and request.method == "GET":
            if "status=eq.ready" in url:
                return httpx.Response(200, json=[])
            return httpx.Response(200, json=[{"status": "failed"}] * 4)
        if "/rest/v1/profile_avatars" in url and request.method == "POST":
            return httpx.Response(201, json=[])
        if "/storage/v1/object/copy" in url:
            return httpx.Response(200, json={"Key": "avatars/aa/fallback.png"})
        if "/rest/v1/rpc/grant_hearts" in url:
            hearts_requests.append(request)
            return httpx.Response(200)
        return httpx.Response(200, json=[])

    router_module._openai_client_override = AsyncMock()
    router_module._openai_client_override.images.edit.side_effect = Exception("openai down")

    client = _wire(handler)
    response = client.post("/profile-onboarding/avatar/generate", headers=AUTH_HEADERS)

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "fallback"
    assert body["compensation_hearts"] == 10
    assert len(hearts_requests) == 1


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
    body = {"nickname": "가나", "height_cm": 170, "phone_number": "01012345678", "gender": "male"}
    client = _wire(lambda request: httpx.Response(200, json=[]))

    just_old_enough = client.post(
        "/profile-onboarding/basic-info", headers=AUTH_HEADERS, json=body | {"birth_year": this_year - 19}
    )
    too_young = client.post(
        "/profile-onboarding/basic-info", headers=AUTH_HEADERS, json=body | {"birth_year": this_year - 18}
    )

    assert just_old_enough.status_code == 200
    assert too_young.status_code == 422
    assert "19" in json.dumps(too_young.json(), ensure_ascii=False)


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

    router_module._vision_client_override = _safe_vision()
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

    router_module._vision_client_override = _safe_vision()
    client = _wire(handler)
    response = client.post(
        "/profile-onboarding/photos",
        headers=AUTH_HEADERS,
        files={"photo": ("a.png", _PNG_BYTES, "image/png")},
        data={"position": "0", "is_avatar_source": "false"},
    )

    assert response.status_code == 409


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
    router_module._openai_client_override = AsyncMock()
    client = _wire(lambda request: httpx.Response(200, json=[{"bio_draft": "저장해 둔 초안이에요"}]))
    response = client.post("/profile-onboarding/bio-draft", headers=AUTH_HEADERS)

    assert response.status_code == 200
    assert response.json()["draft"] == "저장해 둔 초안이에요"
    router_module._openai_client_override.chat.completions.create.assert_not_called()


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
