"""구글 플레이 실시간 알림(POST /billing/play/notifications, 2026-11-14 사용자 결정). Pub/Sub push 가 부른다.

DB(PostgREST)는 가짜다. 인증은 배치와 같은 문(Cloud Scheduler 와 같은 서비스 계정 · audience)이다.
"""
import base64
import hashlib
import json
import logging

import httpx
import pytest
from fastapi.testclient import TestClient

import app.core.batch_auth as batch_auth
from app.core.deps import get_client, get_settings
from app.main import app
from app.settings import Settings

AUDIENCE = "https://campus-mate-backend.example.run.app"
PUSHER = "campus-mate-scheduler@example.iam.gserviceaccount.com"
PACKAGE = "io.github.juunn.campusmate"
A = "11111111-1111-1111-1111-111111111111"
TOKEN = "rtdn-purchase-token-secret"
ORDER = "GPA.3312-3456-7890-12345"


def _sha(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


@pytest.fixture(autouse=True)
def overrides():
    app.dependency_overrides[get_settings] = lambda: Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test",
        batch_audience=AUDIENCE, batch_service_account=PUSHER,
    )
    yield
    app.dependency_overrides.clear()


@pytest.fixture
def pusher(monkeypatch):
    def fake_verify(token, request, audience):
        assert audience == AUDIENCE
        return {"email": PUSHER if token == "id-token" else "someone@else.com", "email_verified": True}

    monkeypatch.setattr(batch_auth.id_token, "verify_oauth2_token", fake_verify)


def _wire(refund: dict | int | None = None):
    """refund: refund_store_purchase 의 답(int 면 그 상태 코드로 실패)."""
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        if request.url.path == "/rest/v1/rpc/refund_store_purchase":
            if isinstance(refund, int):
                return httpx.Response(refund, json={"message": "db down"})
            return httpx.Response(200, json=refund)
        return httpx.Response(404, json={"message": f"unexpected {request.method}"})

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    app.dependency_overrides[get_client] = lambda: client
    return TestClient(app, raise_server_exceptions=False), seen


def _envelope(notification: dict | None = None, *, data: str | None = None) -> dict:
    if data is None:
        data = base64.b64encode(json.dumps(notification).encode()).decode()
    return {"message": {"data": data, "messageId": "136969346945"}, "subscription": "projects/p/subscriptions/s"}


def _voided(product_type=2, refund_type=1, token=TOKEN, package=PACKAGE) -> dict:
    return {"version": "1.0", "packageName": package, "eventTimeMillis": "1791868800000",
            "voidedPurchaseNotification": {"purchaseToken": token, "orderId": ORDER,
                                           "productType": product_type, "refundType": refund_type}}


def _post(test_client: TestClient, body, token: str | None = "id-token"):
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    if isinstance(body, (bytes, str)):
        return test_client.post("/billing/play/notifications", content=body, headers=headers)
    return test_client.post("/billing/play/notifications", json=body, headers=headers)


def _refund_calls(seen):
    return [json.loads(r.content) for r in seen if r.url.path == "/rest/v1/rpc/refund_store_purchase"]


# 인증 -------------------------------------------------------------------------------------------

@pytest.mark.parametrize("token", [None, "wrong-account-token"])
def test_without_the_push_token_it_is_401_like_the_batch_and_nothing_is_touched(pusher, token):
    test_client, seen = _wire({"result": "refunded"})

    response = _post(test_client, _envelope(_voided()), token)

    assert response.status_code == 401
    assert seen == []


@pytest.mark.parametrize("token", [None, "wrong-account-token"])
def test_auth_is_checked_before_the_body_is_read(pusher, token):
    test_client, seen = _wire({"result": "refunded"})

    assert _post(test_client, b"not json", token).status_code == 401
    assert seen == []


def test_the_401_body_is_the_same_as_the_batch(pusher):
    test_client, _ = _wire({"result": "refunded"})
    batch = test_client.post("/batch/billing-voided")

    response = _post(test_client, _envelope(_voided()), None)

    assert (response.status_code, response.json()) == (batch.status_code, batch.json())


# 회수 -------------------------------------------------------------------------------------------

def test_a_fully_voided_one_time_purchase_is_clawed_back_once_by_token_hash(pusher):
    test_client, seen = _wire({"result": "refunded", "profile_id": A, "clawed_back": 50, "shortfall": 0})

    response = _post(test_client, _envelope(_voided()))

    assert response.status_code == 200
    assert response.json() == {"result": "refunded"}
    # DB 로 가는 것은 토큰 해시뿐이다(구글 스토어).
    assert _refund_calls(seen) == [{"p_store": "play_store", "p_token_hash": _sha(TOKEN)}]
    assert not any(TOKEN in r.content.decode() for r in seen if r.content)


@pytest.mark.parametrize("result", ["already_refunded", "unknown"])
def test_already_clawed_back_or_unknown_is_200_and_changes_nothing_more(pusher, result):
    test_client, seen = _wire({"result": result})

    response = _post(test_client, _envelope(_voided()))

    assert response.status_code == 200
    assert response.json() == {"result": result}
    assert len(seen) == 1


def test_a_shortfall_warns_with_only_the_profile_id_and_the_number(pusher, caplog):
    caplog.set_level(logging.DEBUG)
    test_client, _ = _wire({"result": "refunded", "profile_id": A, "clawed_back": 30, "shortfall": 120})

    assert _post(test_client, _envelope(_voided())).status_code == 200
    (warning,) = [r for r in caplog.records if r.levelno == logging.WARNING]
    assert warning.getMessage() == f"환불 회수 부족 profile={A} shortfall=120"


def test_the_result_is_logged_at_info_with_only_safe_fields(pusher, caplog):
    caplog.set_level(logging.INFO)
    test_client, _ = _wire({"result": "refunded", "profile_id": A, "clawed_back": 50, "shortfall": 0})

    _post(test_client, _envelope(_voided()))

    infos = [r.getMessage() for r in caplog.records
             if r.levelno == logging.INFO and r.getMessage().startswith("구글 무효 알림")]
    assert infos == ["구글 무효 알림 orderId=GPA.3312-345 productType=2 refundType=1 result=refunded"]
    for secret in (TOKEN, _sha(TOKEN), ORDER, "id-token"):
        assert secret not in caplog.text, secret


# 할 일 없음 --------------------------------------------------------------------------------------

@pytest.mark.parametrize("body", [
    _envelope({"version": "1.0", "packageName": PACKAGE, "eventTimeMillis": "1",
               "testNotification": {"version": "1.0"}}),
    _envelope({"version": "1.0", "packageName": PACKAGE, "eventTimeMillis": "1",
               "oneTimeProductNotification": {"version": "1.0", "notificationType": 1,
                                              "purchaseToken": TOKEN, "sku": "heart_50"}}),
    _envelope(_voided(package="com.someone.else")),
    _envelope(_voided(product_type=1)),
    _envelope(_voided(refund_type=2)),
    _envelope(_voided(token="")),
    _envelope(data="%%%not-base64%%%"),
    _envelope(data=base64.b64encode(b"not json").decode()),
    _envelope(data=base64.b64encode(b"[1, 2]").decode()),
    {"message": {"messageId": "1"}, "subscription": "s"},
    {"subscription": "s"},
    [1, 2],
    b"not json at all",
    # 깊게 중첩된 JSON — json.loads 가 RecursionError 를 던진다(500 이면 Pub/Sub 이 끝없이 다시 보낸다)
    b"[" * 100_000 + b"]" * 100_000,
    _envelope(data=base64.b64encode(b"[" * 100_000 + b"]" * 100_000).decode()),
    _envelope(_voided(token=12345)),
    _envelope(_voided(token=["a", "b"])),
    # 짝 없는 서로게이트 — token_hash 의 .encode() 가 UnicodeEncodeError 를 던진다
    _envelope(_voided(token="tok\ud800en")),
    _envelope(_voided(product_type="2")),
    _envelope({"version": "1.0", "packageName": PACKAGE, "voidedPurchaseNotification": [TOKEN]}),
], ids=["test", "one_time_product", "other_package", "subscription_product", "partial_refund", "empty_token",
        "broken_base64", "data_not_json", "data_not_object", "no_data", "no_message", "envelope_list",
        "envelope_not_json", "deep_envelope", "deep_data", "token_number", "token_list", "token_lone_surrogate",
        "product_type_string", "voided_list"])
def test_nothing_to_claw_back_is_200_and_the_refund_function_is_not_called(pusher, caplog, body):
    caplog.set_level(logging.INFO)
    test_client, seen = _wire({"result": "refunded"})

    response = _post(test_client, body)

    assert response.status_code == 200
    assert response.json() == {"result": "ignored"}
    assert seen == []
    assert TOKEN not in caplog.text


@pytest.mark.parametrize("notification, level", [
    (_voided(package="com.someone.else"), logging.WARNING),
    (_voided(refund_type=2), logging.WARNING),
    ({"version": "1.0", "packageName": PACKAGE, "testNotification": {"version": "1.0"}}, logging.INFO),
], ids=["other_package", "partial_refund", "test"])
def test_ignored_notifications_leave_one_log_line_at_the_right_level(pusher, caplog, notification, level):
    caplog.set_level(logging.INFO)
    test_client, _ = _wire()

    _post(test_client, _envelope(notification))

    mine = [r for r in caplog.records if r.name == "app.billing.batch_router"]
    assert [r.levelno for r in mine] == [level]


@pytest.mark.parametrize("voided, expected", [
    (_voided(product_type="2"), "productType='2' refundType=1 token=True"),
    (_voided(token=12345), "productType=2 refundType=1 token=False"),
    (_voided(token="tok\ud800en"), "productType=2 refundType=1 token=True"),
], ids=["product_type_string", "token_number", "token_lone_surrogate"])
def test_the_skip_warning_shows_the_cause_without_the_token(pusher, caplog, voided, expected):
    caplog.set_level(logging.INFO)
    test_client, _ = _wire()

    _post(test_client, _envelope(voided))

    (warning,) = [r.getMessage() for r in caplog.records if r.levelno == logging.WARNING]
    # 줄 전체를 맞춘다 — 토큰 원문이 끼어들 자리가 없다.
    assert warning == f"구글 무효 알림 회수 안 함 orderId=GPA.3312-345 {expected}"


def test_an_unreadable_envelope_warns(pusher, caplog):
    caplog.set_level(logging.INFO)
    test_client, _ = _wire()

    _post(test_client, _envelope(data="%%%not-base64%%%"))

    mine = [r for r in caplog.records if r.name == "app.billing.batch_router"]
    assert [r.levelno for r in mine] == [logging.WARNING]


# DB 실패 ----------------------------------------------------------------------------------------

@pytest.mark.parametrize("status", [500, 503])
def test_a_database_failure_is_5xx_so_pubsub_redelivers(pusher, status):
    test_client, seen = _wire(status)

    response = _post(test_client, _envelope(_voided()))

    assert response.status_code >= 500
    assert len(_refund_calls(seen)) == 1
