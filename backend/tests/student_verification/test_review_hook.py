"""학생증 검토 결과 알림 훅(결함 A7 · 결정 3). DB 트리거가 pending → verified/rejected 때 부른다."""
import json
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


def _wire(status: str | None, pushes: list[dict]) -> TestClient:
    """profiles 의 지금 상태 · 알림 스위치 · 토큰 한 개를 돌려주고, FCM 으로 간 본문을 모은다. status None = 프로필 행 없음."""
    def handler(request: httpx.Request) -> httpx.Response:
        if "fcm.googleapis.com" in str(request.url):
            pushes.append(json.loads(request.content))
            return httpx.Response(200, json={"name": "projects/x/messages/1"})
        table = request.url.path.rsplit("/", 1)[-1]
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
