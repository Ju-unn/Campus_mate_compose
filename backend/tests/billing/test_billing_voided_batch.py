"""환불 회수 배치(POST /batch/billing-voided) — 계획서 8-1 B1~B5. 구글 무효 구매 목록은 가짜다(실제 호출 없음)."""
import hashlib
import json
import logging
from datetime import datetime, timedelta

import httpx
import pytest
from fastapi.testclient import TestClient

import app.core.batch_auth as batch_auth
from app.billing.play import PlayApi
from app.billing.router import play_api_dependency
from app.core.deps import get_client, get_now, get_settings
from app.core.time import SEOUL
from app.main import app
from app.settings import Settings

AUDIENCE = "https://campus-mate-backend.example.run.app"
SCHEDULER = "campus-mate-scheduler@example.iam.gserviceaccount.com"
NOW = datetime(2026, 10, 13, 15, 15, tzinfo=SEOUL)
A = "11111111-1111-1111-1111-111111111111"
T1, T2, T3 = "voided-token-1", "voided-token-2", "voided-token-3"


def _sha(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


@pytest.fixture(autouse=True)
def overrides():
    app.dependency_overrides[get_settings] = lambda: Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test",
        batch_audience=AUDIENCE, batch_service_account=SCHEDULER,
    )
    app.dependency_overrides[get_now] = lambda: NOW
    yield
    app.dependency_overrides.clear()


@pytest.fixture
def scheduler(monkeypatch):
    def fake_verify(token, request, audience):
        assert audience == AUDIENCE
        return {"email": SCHEDULER if token == "id-token" else "someone@else.com", "email_verified": True}

    monkeypatch.setattr(batch_auth.id_token, "verify_oauth2_token", fake_verify)


def _wire(pages: list[dict] | int, refunds: dict[str, dict] | None = None, purged: int = 0):
    """pages: 구글 무효 목록의 쪽들(int 면 그 상태 코드). refunds: 토큰 해시 → refund_store_purchase 답."""
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        if request.url.host == "androidpublisher.googleapis.com":
            if isinstance(pages, int):
                return httpx.Response(pages)
            index = int(request.url.params.get("token", "0"))
            return httpx.Response(200, json=pages[index])
        if request.url.path == "/rest/v1/rpc/refund_store_purchase":
            return httpx.Response(200, json=(refunds or {})[json.loads(request.content)["p_token_hash"]])
        if request.url.path == "/rest/v1/purchases" and request.method == "DELETE":
            return httpx.Response(200, json=[{"id": f"p{n}"} for n in range(purged)])
        return httpx.Response(404, json={"message": f"unexpected {request.method}"})

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))

    async def fixed_token() -> str:
        return "play-access-token"

    app.dependency_overrides[get_client] = lambda: client
    app.dependency_overrides[play_api_dependency] = lambda: PlayApi(client, access_token=fixed_token)
    return TestClient(app), seen


def _run(test_client: TestClient, token: str | None = "id-token"):
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    return test_client.post("/batch/billing-voided", headers=headers)


def _google(seen):
    return [r for r in seen if r.url.host == "androidpublisher.googleapis.com"]


def _refund_calls(seen):
    return [json.loads(r.content) for r in seen if r.url.path == "/rest/v1/rpc/refund_store_purchase"]


def _deletes(seen):
    return [r for r in seen if r.method == "DELETE"]


# B1 ---------------------------------------------------------------------------------------------

@pytest.mark.parametrize("token", [None, "wrong-account-token"])
def test_without_the_scheduler_token_it_is_401_and_google_is_not_asked(scheduler, token):
    test_client, seen = _wire([{}])

    assert _run(test_client, token).status_code == 401
    assert seen == []


# B2 ---------------------------------------------------------------------------------------------

def test_every_page_is_followed_and_each_voided_purchase_is_clawed_back_once(scheduler):
    pages = [
        {"voidedPurchases": [{"purchaseToken": T1, "orderId": "GPA.1"}], "tokenPagination": {"nextPageToken": "1"}},
        {"voidedPurchases": [{"purchaseToken": T2, "orderId": "GPA.2"}, {"purchaseToken": T3, "orderId": "GPA.3"}]},
    ]
    refunds = {
        _sha(T1): {"result": "refunded", "profile_id": A, "clawed_back": 150, "shortfall": 0},
        _sha(T2): {"result": "unknown"},
        _sha(T3): {"result": "already_refunded"},
    }
    test_client, seen = _wire(pages, refunds, purged=2)
    response = _run(test_client)

    assert response.status_code == 200
    assert response.json() == {"voided": 3, "refunded": 1, "already_refunded": 1, "unknown": 1, "purged": 2}
    assert len(_google(seen)) == 2
    # 매시 돌지만 7일을 본다 — 배치가 며칠 실패해도 놓치지 않는다(구글은 30일치를 주고, 처리가 멱등이라 겹쳐도 된다).
    assert _google(seen)[0].url.params["startTime"] == str(int((NOW - timedelta(days=7)).timestamp() * 1000))
    # DB 로 가는 것은 토큰 해시뿐이다.
    assert _refund_calls(seen) == [{"p_store": "play_store", "p_token_hash": _sha(t)} for t in (T1, T2, T3)]
    assert not any(t in r.content.decode() for r in seen for t in (T1, T2, T3) if r.content)


def test_nothing_voided_still_purges_and_answers_zero(scheduler):
    test_client, seen = _wire([{}])

    assert _run(test_client).json() == {"voided": 0, "refunded": 0, "already_refunded": 0, "unknown": 0, "purged": 0}
    assert len(_deletes(seen)) == 1


# B3 ---------------------------------------------------------------------------------------------

def test_a_shortfall_warns_with_only_the_profile_id_and_the_number(scheduler, caplog):
    caplog.set_level(logging.DEBUG)
    refunds = {_sha(T1): {"result": "refunded", "profile_id": A, "clawed_back": 30, "shortfall": 120}}
    test_client, _ = _wire([{"voidedPurchases": [{"purchaseToken": T1, "orderId": "GPA.secret-order"}]}], refunds)

    assert _run(test_client).status_code == 200
    (warning,) = [r for r in caplog.records if r.levelno == logging.WARNING]
    assert A in warning.getMessage() and "120" in warning.getMessage()
    assert T1 not in caplog.text and _sha(T1) not in caplog.text and "GPA.secret-order" not in caplog.text


# B4 ---------------------------------------------------------------------------------------------

@pytest.mark.parametrize("status", [500, 403, 400])
def test_google_outage_is_503_and_nothing_is_touched(scheduler, status):
    test_client, seen = _wire(status)

    assert _run(test_client).status_code == 503
    assert _refund_calls(seen) == [] and _deletes(seen) == []


# B5 ---------------------------------------------------------------------------------------------

def test_purge_removes_records_past_retention_and_test_purchases_of_deleted_accounts(scheduler):
    test_client, seen = _wire([{}])
    _run(test_client)

    (delete,) = _deletes(seen)
    assert delete.url.path == "/rest/v1/purchases"
    # 5년 = 365일 × 5 + 윤일 2일(5년 안에 윤일이 최대 2번) — 5년이 다 차기 전에 지우지 않는다.
    cutoff = (NOW - timedelta(days=5 * 365 + 2)).isoformat()
    assert delete.url.params["or"] == f"(purchased_at.lt.{cutoff},and(is_test.is.true,profile_id.is.null))"
    assert delete.headers["Prefer"] == "return=representation"
