"""학생증 검토 결과 알림 훅(결함 A7 · 결정 3). DB 트리거가 pending → verified/rejected 때 부른다."""
import json
import logging
from datetime import datetime

import httpx
import pytest
from fastapi.testclient import TestClient

from app.cards.push import FcmSender
from app.cards.router import get_sender
from app.core.deps import get_client, get_now, get_settings
from app.core.time import SEOUL
from app.main import app
from app.settings import Settings
from app.student_verification.retention import EXPIRED_REASON

ME = "11111111-1111-1111-1111-111111111111"
SECRET = "hook-secret-test"
URL = "/hooks/verification-reviewed"
NOON = datetime(2026, 10, 3, 12, 0, tzinfo=SEOUL)


class _FakeCredentials:
    token = "fake-access-token"
    valid = True

    def refresh(self, _request) -> None:
        pass


def _settings(secret: str = SECRET) -> Settings:
    return Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test",
        verification_hook_secret=secret,
    )


@pytest.fixture(autouse=True)
def overrides():
    app.dependency_overrides[get_settings] = _settings
    app.dependency_overrides[get_now] = lambda: NOON
    yield
    app.dependency_overrides.clear()


PHOTO = f"{ME}/photo-5.jpg"
ATTEMPT = {"id": 5, "file_path": PHOTO, "reject_reason": None, "result": "verified"}


def _wire(status: str | None, pushes: list[dict], *, attempt: dict | None = None, deletes: list[str] | None = None,
          delete_status: int = 200, attempt_lookup_fails: bool = False) -> TestClient:
    """profiles 의 지금 상태 · 알림 스위치 · 토큰 한 개를 돌려주고, FCM 으로 간 본문을 모은다. status None = 프로필 행 없음.
    attempt 는 그 사람의 가장 최근 학생증 시도 한 줄, deletes 는 Storage 로 간 삭제 요청 경로를 모은다."""
    def handler(request: httpx.Request) -> httpx.Response:
        if "fcm.googleapis.com" in str(request.url):
            pushes.append(json.loads(request.content))
            return httpx.Response(200, json={"name": "projects/x/messages/1"})
        if request.method == "DELETE" and "/object/student-id-temp/" in request.url.path:
            if deletes is not None:
                deletes.append(request.url.path.split("/object/student-id-temp/", 1)[1])
            return httpx.Response(delete_status, json=[])
        table = request.url.path.rsplit("/", 1)[-1]
        if table == "student_verification_attempts":
            if attempt_lookup_fails:
                return httpx.Response(500, json={"message": "boom"})
            return httpx.Response(200, json=[attempt] if attempt else [])
        select = request.url.params.get("select", "")
        if table == "profiles" and status is None:
            return httpx.Response(200, json=[])
        if table == "profiles" and "student_verification" in select:
            return httpx.Response(200, json=[{"student_verification": status, "department": None,
                                              "universities": {"name": "테스트대학교"}, "status": "active"}])
        if table == "profiles":
            return httpx.Response(200, json=[{"status": "active"}])
        if table == "push_tokens":
            return httpx.Response(200, json=[{"token": "device-1"}])
        return httpx.Response(200, json=[])

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    app.dependency_overrides[get_client] = lambda: client
    app.dependency_overrides[get_sender] = lambda: FcmSender("campus-mate-test", client, credentials=_FakeCredentials())
    return TestClient(app)


def _notification(push: dict) -> tuple[str, str, dict]:
    message = push["message"]
    return message["notification"]["title"], message["notification"]["body"], message["data"]


def test_verified_sends_pass_notification():
    pushes: list[dict] = []
    response = _wire("verified", pushes).post(URL, json={"profile_id": ME}, headers={"x-webhook-secret": SECRET})

    assert response.status_code == 200
    assert response.json() == {"sent": 1}
    assert _notification(pushes[0]) == ("학생 인증이 끝났어요", "학과 정보를 입력하고 시작해 보세요",
                                        {"route": "verification"})


def test_rejected_sends_retry_notification_without_reason():
    pushes: list[dict] = []
    response = _wire("rejected", pushes).post(URL, json={"profile_id": ME}, headers={"x-webhook-secret": SECRET})

    assert response.json() == {"sent": 1}
    assert _notification(pushes[0]) == ("학생 인증을 다시 해 주세요", "서류를 확인하지 못했어요. 앱에서 이유를 확인해 주세요",
                                        {"route": "verification"})


def test_reads_status_again_instead_of_trusting_the_body():
    # 트리거가 부른 뒤 대시보드에서 다시 pending 으로 돌렸으면 보내지 않는다 — 본문엔 상태를 받지도 않는다.
    pushes: list[dict] = []
    response = _wire("pending", pushes).post(URL, json={"profile_id": ME}, headers={"x-webhook-secret": SECRET})

    assert response.status_code == 200
    assert response.json() == {"sent": 0}
    assert pushes == []


def test_missing_profile_ends_quietly_instead_of_500():
    # 탈퇴 정리 뒤 늦게 온 호출 등 — pg_net 은 다시 보내지 않으니 오류로 남길 일이 아니다(운영 10-03 확인).
    pushes: list[dict] = []
    response = _wire(None, pushes).post(URL, json={"profile_id": ME}, headers={"x-webhook-secret": SECRET})

    assert response.status_code == 200
    assert response.json() == {"sent": 0}
    assert pushes == []


@pytest.mark.parametrize("headers", [{}, {"x-webhook-secret": "wrong"}])
def test_wrong_or_missing_secret_is_401(headers):
    pushes: list[dict] = []
    response = _wire("verified", pushes).post(URL, json={"profile_id": ME}, headers=headers)

    assert response.status_code == 401
    assert pushes == []


def test_unset_secret_lets_nobody_in():
    # 시크릿을 빠뜨린 배포가 열린 문이 되지 않게 — 빈 헤더와 빈 설정이 같다고 통과시키지 않는다.
    app.dependency_overrides[get_settings] = lambda: _settings(secret="")
    pushes: list[dict] = []
    response = _wire("verified", pushes).post(URL, json={"profile_id": ME}, headers={"x-webhook-secret": ""})

    assert response.status_code == 401
    assert pushes == []


# 사진 삭제(사용자 결정 2026-10-11): 사람이 재검토해 확정하면 학생증 사진을 서버가 지운다 ----------------

@pytest.mark.parametrize("status", ["verified", "rejected"])
def test_a_human_review_deletes_the_attempts_photo(status):
    deletes: list[str] = []
    response = _wire(status, [], attempt=ATTEMPT, deletes=deletes).post(
        URL, json={"profile_id": ME}, headers={"x-webhook-secret": SECRET})

    assert response.status_code == 200
    assert deletes == [PHOTO]


def test_still_pending_deletes_nothing():
    deletes: list[str] = []
    _wire("pending", [], attempt=ATTEMPT, deletes=deletes).post(
        URL, json={"profile_id": ME}, headers={"x-webhook-secret": SECRET})

    assert deletes == []


def test_a_failed_delete_does_not_block_the_hook_and_logs_only_the_attempt_id(caplog):
    pushes: list[dict] = []
    deletes: list[str] = []
    with caplog.at_level(logging.DEBUG, logger="app"):
        response = _wire("verified", pushes, attempt=ATTEMPT, deletes=deletes, delete_status=500).post(
            URL, json={"profile_id": ME}, headers={"x-webhook-secret": SECRET})

    assert response.status_code == 200
    assert response.json() == {"sent": 1}
    assert deletes == [PHOTO]  # 지우려 했지만 실패 — 매시 배치가 이어서 지운다
    assert "attempt=5" in caplog.text
    assert PHOTO not in caplog.text and "photo-5" not in caplog.text and ME not in caplog.text


def test_a_failed_attempt_lookup_does_not_block_the_hook(caplog):
    pushes: list[dict] = []
    with caplog.at_level(logging.DEBUG, logger="app"):
        response = _wire("verified", pushes, attempt_lookup_fails=True).post(
            URL, json={"profile_id": ME}, headers={"x-webhook-secret": SECRET})

    assert response.status_code == 200
    assert response.json() == {"sent": 1}
    assert ME not in caplog.text and "service-key" not in caplog.text


def test_no_attempt_row_deletes_nothing_and_still_notifies():
    deletes: list[str] = []
    response = _wire("verified", [], attempt=None, deletes=deletes).post(
        URL, json={"profile_id": ME}, headers={"x-webhook-secret": SECRET})

    assert response.json() == {"sent": 1}
    assert deletes == []


def test_an_expired_review_gets_its_own_message():
    pushes: list[dict] = []
    expired = {**ATTEMPT, "reject_reason": EXPIRED_REASON}
    response = _wire("rejected", pushes, attempt=expired).post(
        URL, json={"profile_id": ME}, headers={"x-webhook-secret": SECRET})

    assert response.json() == {"sent": 1}
    assert _notification(pushes[0]) == ("학생 인증을 다시 해 주세요",
                                        "검토 기한이 지나 사진을 삭제했어요. 학생증을 다시 올려 주세요",
                                        {"route": "verification"})


def test_a_latest_attempt_still_pending_keeps_its_photo():
    # 프로필만 먼저 바뀌고 시도 행은 아직 대기 — 사람이 아직 확정하지 않은 사진이다(30일 안에 배치가 닫는다).
    deletes: list[str] = []
    response = _wire("verified", [], attempt={**ATTEMPT, "result": "pending"}, deletes=deletes).post(
        URL, json={"profile_id": ME}, headers={"x-webhook-secret": SECRET})

    assert response.json() == {"sent": 1}
    assert deletes == []


def test_an_unexpected_error_while_deleting_does_not_block_the_hook(monkeypatch):
    async def explode(self, path):
        raise RuntimeError("boom")

    monkeypatch.setattr("app.student_verification.review_hook.StudentIdStorage.delete", explode)
    pushes: list[dict] = []
    response = _wire("verified", pushes, attempt=ATTEMPT).post(
        URL, json={"profile_id": ME}, headers={"x-webhook-secret": SECRET})

    assert response.status_code == 200
    assert response.json() == {"sent": 1}
