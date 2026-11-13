"""인앱결제 확인(POST /billing/google/verify) · 상점 상태(GET /billing/status) — 계획서 8-1 V1~V14 · S1 · R1.

구글은 httpx.MockTransport 로 답을 정한다(실제 호출 없음). DB 함수 grant_store_purchase 의 답도 가짜다 —
함수 자체는 pgTAP(supabase/tests/purchases_test.sql)이 본다.
"""
import hashlib
import json
import logging

import httpx
import pytest
from fastapi.testclient import TestClient

from app.billing.apple import apple_account_token
from app.billing.play import PlayApi, account_token
from app.billing.router import play_api_dependency
from app.core import errors
from app.core.deps import get_client, get_settings
from app.main import app
from app.settings import Settings

PROFILE_ID = "11111111-1111-1111-1111-111111111111"
AUTH = {"Authorization": "Bearer valid-token"}
TOKEN = "opaque-token.AbC_123-xyz"
ORDER = "GPA.1234-5678-9012-34567"
GRANTED = {"result": "granted", "hearts": 100, "bonus_hearts": 50, "heart_balance": 150}


@pytest.fixture(autouse=True)
def overrides():
    app.dependency_overrides[get_settings] = lambda: Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test",
    )
    yield
    app.dependency_overrides.clear()


def _purchase(**changed) -> dict:
    base = {"purchaseState": 0, "consumptionState": 0, "orderId": ORDER, "purchaseTimeMillis": "1760300000000",
            "obfuscatedExternalAccountId": account_token(PROFILE_ID), "quantity": 1, "productId": "heart_100"}
    return {**base, **changed}


def _filtered(rows: list, params) -> list:
    """PostgREST 가짜가 heart_amount=gte.N 조건을 실제로 적용한다 — 조건을 안 보내면 모든 행이 돌아와 시험이 잡는다."""
    floor = params.get("heart_amount")
    if floor is not None:
        assert floor.startswith("gte."), floor
        rows = [row for row in rows if row["heart_amount"] >= int(floor.removeprefix("gte."))]
    return rows


def _answer(value) -> httpx.Response:
    """dict = 200 본문, int = 그 상태 코드, 예외 = 던짐."""
    if isinstance(value, Exception):
        raise value
    return httpx.Response(value, json={"error": {}}) if isinstance(value, int) else httpx.Response(200, json=value)


def _line_items(product_ids: list[str]) -> dict:
    return {"productLineItem": [{"productId": p, "productOfferDetails": {"quantity": 1}} for p in product_ids]}


def _wire(google=None, rpc: dict | None = None, consume: int = 200, purchases: list | None = None,
          v2=_line_items(["heart_100"])):
    """google: v1 구매 조회 답, v2: v2(productsv2) 조회 답 — 둘 다 _answer 모양. seen 에는 관문 밖 요청만 쌓인다."""
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if "/auth/v1/user" in str(request.url):
            return httpx.Response(200, json={"id": PROFILE_ID})
        # 관문 조회는 select 키로 가른다(reference_backend_test_mock_traps).
        if request.method == "GET" and "student_verification" in request.url.params.get("select", ""):
            return httpx.Response(200, json=[{"student_verification": "verified", "department": "컴공",
                                              "school_email_verified_at": "2026-10-01T00:00:00+00:00"}])
        seen.append(request)
        if request.url.host == "androidpublisher.googleapis.com":
            if request.url.path.endswith(":consume"):
                return httpx.Response(consume)
            if "/purchases/productsv2/" in request.url.path:
                return _answer(v2)
            return _answer(google)
        if request.url.path == "/rest/v1/rpc/grant_store_purchase":
            return httpx.Response(200, json=rpc)
        if request.url.path == "/rest/v1/purchases" and request.method == "GET":
            return httpx.Response(200, json=_filtered(purchases or [], request.url.params))
        return httpx.Response(404, json={"message": f"unexpected {request.method}"})

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))

    async def fixed_token() -> str:
        return "play-access-token"

    app.dependency_overrides[get_client] = lambda: client
    app.dependency_overrides[play_api_dependency] = lambda: PlayApi(client, access_token=fixed_token)
    return TestClient(app, raise_server_exceptions=False), seen


def _verify(test_client: TestClient, product_id: str = "heart_100", token: str = TOKEN, headers: dict = AUTH):
    return test_client.post("/billing/google/verify", headers=headers,
                            json={"product_id": product_id, "purchase_token": token})


def _rpc_calls(seen):
    return [r for r in seen if r.url.path == "/rest/v1/rpc/grant_store_purchase"]


def _consumes(seen):
    return [r for r in seen if r.url.path.endswith(":consume")]


def _google(seen):
    return [r for r in seen if r.url.host == "androidpublisher.googleapis.com"]


def _v2_calls(seen):
    return [r for r in seen if "/purchases/productsv2/" in r.url.path]


# V1 ---------------------------------------------------------------------------------------------

def test_first_purchase_grants_hearts_with_bonus_and_consumes():
    test_client, seen = _wire(_purchase(), rpc=GRANTED)
    response = _verify(test_client)

    assert response.status_code == 200
    assert response.json() == GRANTED
    (rpc,) = _rpc_calls(seen)
    body = json.loads(rpc.content)
    assert body == {
        "p_profile_id": PROFILE_ID, "p_store": "play_store", "p_product_id": "heart_100",
        "p_token_hash": hashlib.sha256(TOKEN.encode()).hexdigest(), "p_order_id": ORDER,
        "p_purchased_at": "2025-10-12T20:13:20+00:00", "p_is_test": False,
    }
    # 토큰 원문은 DB 로 가지 않는다 — 해시만.
    assert TOKEN not in rpc.content.decode()
    assert len(_consumes(seen)) == 1
    # 소비는 지급이 끝난 뒤다(순서가 반대면 지급 실패 때 구매가 사라진다).
    assert seen.index(_consumes(seen)[0]) > seen.index(rpc)
    # 산 상품 대조(v2)는 지급 전이다.
    (v2,) = _v2_calls(seen)
    assert seen.index(v2) < seen.index(rpc)


# P1 · 산 상품 = 지급 상품 — v1 답에는 productId 가 없어(운영 11-13) v2 productLineItem 으로 대조한다 ------------

@pytest.mark.parametrize("v2", [
    _line_items(["heart_50"]),  # 50하트를 사고 800하트… 가 아니라 100하트 주소로 확인 요청
    _line_items(["heart_100", "heart_100"]),
    _line_items(["heart_100", "heart_800"]),
    _line_items([]),
    {},
    400, 404, 410,  # v1 은 알지만 v2 는 모르는 토큰 — v1 과 같게 "확인되지 않는 구매"
])
def test_a_purchase_whose_v2_products_are_not_exactly_the_requested_one_is_invalid(v2):
    test_client, seen = _wire(_purchase(), rpc=GRANTED, v2=v2)
    response = _verify(test_client)

    assert response.status_code == 422
    assert response.json() == {"detail": errors.PURCHASE_INVALID, "code": "purchase_invalid"}
    assert _rpc_calls(seen) == [] and _consumes(seen) == []


@pytest.mark.parametrize("v2", [500, 503, 429, 401, 403, httpx.ConnectTimeout("slow")])
def test_a_v2_outage_is_503_and_nothing_is_granted(v2):
    test_client, seen = _wire(_purchase(), rpc=GRANTED, v2=v2)
    response = _verify(test_client)

    assert response.status_code == 503
    assert response.json() == {"detail": errors.BILLING_UNAVAILABLE, "code": "billing_unavailable"}
    assert _rpc_calls(seen) == [] and _consumes(seen) == []


def test_a_resent_token_is_still_checked_against_v2_before_already_granted():
    already = {**GRANTED, "result": "already_granted"}
    test_client, seen = _wire(_purchase(consumptionState=1), rpc=already, v2=_line_items(["heart_50"]))

    assert _verify(test_client).status_code == 422
    assert _rpc_calls(seen) == []


@pytest.mark.parametrize("v2", [_line_items(["heart_100"]), _line_items(["heart_50"]), 404, 500])
def test_the_v2_products_are_logged_with_a_match_flag(v2, caplog):
    caplog.set_level(logging.INFO)
    test_client, _ = _wire(_purchase(), rpc=GRANTED, v2=v2)
    _verify(test_client)

    lines = [r.getMessage() for r in caplog.records if r.getMessage().startswith("구글 구매 상품 대조")]
    if v2 == 500:
        assert lines == []  # 조회 실패는 기존 "구글 구매 조회 실패" 경고 한 줄
        return
    (message,) = lines
    products = [i["productId"] for i in v2["productLineItem"]] if isinstance(v2, dict) else None  # 404 → None
    assert f"profile={PROFILE_ID}" in message and "product=heart_100" in message
    assert f"v2_products={products}" in message and f"match={products == ['heart_100']}" in message
    _assert_no_purchase_values(caplog)


# V2 ---------------------------------------------------------------------------------------------

@pytest.mark.parametrize("google, rpc, consume", [
    (500, None, 200),
    (403, None, 200),
    (httpx.ReadTimeout(f"timed out .../tokens/{TOKEN}"), None, 200),
    (_purchase(obfuscatedExternalAccountId="someone-else"), None, 200),
    (_purchase(), {"result": "token_used"}, 200),
    (_purchase(), GRANTED, 500),
])
def test_logs_never_contain_the_token_or_order_id(google, rpc, consume, caplog):
    caplog.set_level(logging.DEBUG)
    test_client, _ = _wire(google, rpc=rpc, consume=consume)
    _verify(test_client)

    assert caplog.records, "실패 경로는 경고 한 줄을 남긴다 — 비면 이 시험이 아무것도 보지 않는다"
    for record in caplog.records:
        assert TOKEN not in record.getMessage() and ORDER not in record.getMessage(), record.getMessage()
    assert TOKEN not in caplog.text and ORDER not in caplog.text


@pytest.mark.parametrize("v2", [
    500, 404, httpx.ReadTimeout(f"timed out .../productsv2/tokens/{TOKEN}"),
    {**_line_items(["heart_800"]), "orderId": ORDER}, _line_items(["heart_100"]),
])
def test_logs_of_the_v2_lookup_never_contain_the_token_or_order_id(v2, caplog):
    caplog.set_level(logging.DEBUG)
    test_client, _ = _wire(_purchase(), rpc=GRANTED, v2=v2)
    _verify(test_client)

    assert caplog.records, "실패 경로는 경고 한 줄을 남긴다 — 비면 이 시험이 아무것도 보지 않는다"
    for record in caplog.records:
        assert TOKEN not in record.getMessage() and ORDER not in record.getMessage(), record.getMessage()
    assert TOKEN not in caplog.text and ORDER not in caplog.text


# L1 · 운영 기록 — 구글이 productId 를 실제로 주는지 기록으로 판단한다(값은 찍지 않는다) ------------------

def _info(caplog, prefix: str) -> str:
    (message,) = [r.getMessage() for r in caplog.records if r.levelno == logging.INFO and r.getMessage().startswith(prefix)]
    return message


def _assert_no_purchase_values(caplog):
    for secret in (TOKEN, ORDER, account_token(PROFILE_ID)):
        assert secret not in caplog.text, secret


def test_the_google_answer_is_logged_by_key_names_when_product_id_is_missing(caplog):
    caplog.set_level(logging.INFO)
    google = _purchase()
    del google["productId"]
    test_client, _ = _wire(google, rpc=GRANTED)
    assert _verify(test_client).status_code == 200

    message = _info(caplog, "구글 구매 조회 응답")
    assert f"profile={PROFILE_ID}" in message and "product=heart_100" in message
    assert f"keys={sorted(google)}" in message
    assert "has_product_id=False" in message and "product_match=None" in message
    assert "state=0" in message and "consumption=0" in message
    _assert_no_purchase_values(caplog)


@pytest.mark.parametrize("google_product, match", [("heart_100", True), ("heart_50", False)])
def test_the_google_answer_says_whether_its_product_id_matches(google_product, match, caplog):
    caplog.set_level(logging.INFO)
    test_client, _ = _wire(_purchase(productId=google_product), rpc=GRANTED)
    _verify(test_client)

    message = _info(caplog, "구글 구매 조회 응답")
    assert "has_product_id=True" in message and f"product_match={match}" in message
    _assert_no_purchase_values(caplog)


def test_a_grant_is_logged_with_its_result_and_hearts(caplog):
    caplog.set_level(logging.INFO)
    test_client, _ = _wire(_purchase(), rpc=GRANTED)
    _verify(test_client)

    message = _info(caplog, "구글 구매 지급")
    assert f"profile={PROFILE_ID}" in message and "product=heart_100" in message
    assert "result=granted" in message and "hearts=100" in message and "bonus_hearts=50" in message
    _assert_no_purchase_values(caplog)


# V3 · 재전송 ------------------------------------------------------------------------------------

def test_the_same_token_already_consumed_is_answered_without_consuming_again():
    already = {**GRANTED, "result": "already_granted"}
    test_client, seen = _wire(_purchase(consumptionState=1), rpc=already)
    response = _verify(test_client)

    assert response.status_code == 200 and response.json() == already
    assert _consumes(seen) == []


def test_a_granted_purchase_whose_consume_failed_is_consumed_on_the_retry():
    # 지난번 소비가 실패해 구글 쪽이 아직 미소비 — 다시 보내면 하트는 그대로(already_granted)이고 소비만 다시 한다.
    test_client, seen = _wire(_purchase(consumptionState=0), rpc={**GRANTED, "result": "already_granted"})

    assert _verify(test_client).json()["result"] == "already_granted"
    assert len(_consumes(seen)) == 1


# V4 ---------------------------------------------------------------------------------------------

def test_pending_purchase_is_not_granted():
    test_client, seen = _wire(_purchase(purchaseState=2))
    response = _verify(test_client)

    assert response.status_code == 202 and response.json() == {"result": "pending"}
    assert _rpc_calls(seen) == [] and _consumes(seen) == []
    # 대기는 지금처럼 v1 답만으로 202 — v2 가 멈춰도 대기 응답이 바뀌지 않는다.
    assert _v2_calls(seen) == []


# V5 · V6 ----------------------------------------------------------------------------------------

@pytest.mark.parametrize("google", [
    _purchase(purchaseState=1), _purchase(quantity=2), 400, 404, 410,
    # 주소의 상품과 다른 상품의 구매(구글이 productId 를 알려 줄 때) — 50하트를 사고 800하트로 받으려는 요청.
    _purchase(productId="heart_50"),
])
def test_a_purchase_google_does_not_vouch_for_is_invalid(google):
    test_client, seen = _wire(google)
    response = _verify(test_client)

    assert response.status_code == 422
    assert response.json() == {"detail": errors.PURCHASE_INVALID, "code": "purchase_invalid"}
    assert _rpc_calls(seen) == [] and _consumes(seen) == []


# V7 ---------------------------------------------------------------------------------------------

@pytest.mark.parametrize("google", [500, 503, 429, 401, 403, httpx.ConnectTimeout("slow")])
def test_google_outage_is_503_and_nothing_is_granted(google):
    test_client, seen = _wire(google)
    response = _verify(test_client)

    assert response.status_code == 503
    assert response.json() == {"detail": errors.BILLING_UNAVAILABLE, "code": "billing_unavailable"}
    assert _rpc_calls(seen) == [] and _consumes(seen) == []


# V8 ---------------------------------------------------------------------------------------------

@pytest.mark.parametrize("marker", ["someone-else", None])
def test_purchase_made_for_another_account_is_refused_and_not_consumed(marker):
    google = _purchase(obfuscatedExternalAccountId=marker)
    if marker is None:
        del google["obfuscatedExternalAccountId"]
    test_client, seen = _wire(google)
    response = _verify(test_client)

    assert response.status_code == 409
    assert response.json() == {"detail": errors.PURCHASE_OTHER_ACCOUNT, "code": "purchase_other_account"}
    # 소비하지 않는다 — 원래 계정으로 로그인하면 이어서 받고, 3일 안에 안 오면 구글이 돈을 돌려준다.
    assert _rpc_calls(seen) == [] and _consumes(seen) == []


# V9 ---------------------------------------------------------------------------------------------

def test_a_token_another_account_already_used_is_409_and_not_consumed():
    test_client, seen = _wire(_purchase(), rpc={"result": "token_used"})
    response = _verify(test_client)

    assert response.status_code == 409
    assert response.json() == {"detail": errors.PURCHASE_TOKEN_USED, "code": "purchase_token_used"}
    assert _consumes(seen) == []


# V10 --------------------------------------------------------------------------------------------

def test_a_failed_consume_still_answers_granted_and_warns(caplog):
    caplog.set_level(logging.WARNING)
    test_client, seen = _wire(_purchase(), rpc=GRANTED, consume=500)
    response = _verify(test_client)

    assert response.status_code == 200 and response.json() == GRANTED
    assert len(_consumes(seen)) == 1
    assert any("소비 실패" in r.getMessage() and PROFILE_ID in r.getMessage() for r in caplog.records)


# V11 --------------------------------------------------------------------------------------------

@pytest.mark.parametrize("purchase_type, is_test", [(0, True), (None, False), (1, False)])
def test_a_license_tester_purchase_is_marked_as_test(purchase_type, is_test):
    google = _purchase() if purchase_type is None else _purchase(purchaseType=purchase_type)
    test_client, seen = _wire(google, rpc=GRANTED)
    _verify(test_client)

    assert json.loads(_rpc_calls(seen)[0].content)["p_is_test"] is is_test


# V12 --------------------------------------------------------------------------------------------

@pytest.mark.parametrize("rpc", [{"result": "unknown_product"}, {"result": "surprise"}, {}])
def test_an_answer_outside_the_contract_is_500_and_not_consumed(rpc):
    test_client, seen = _wire(_purchase(), rpc=rpc)

    assert _verify(test_client).status_code == 500
    # 반쪽 성공을 만들지 않는다 — 지급 여부를 모르면 구매를 끝내지 않는다(앱이 다시 보낸다).
    assert _consumes(seen) == []


# V13 --------------------------------------------------------------------------------------------

@pytest.mark.parametrize("product_id, token", [
    ("heart_999", TOKEN), ("heart_100", "a/b"), ("heart_100", "a b"), ("heart_100", "x" * 1001),
    ("heart_100", ""), ("heart_100", ".dot-first"), ("heart_100", "../../voidedpurchases"),
])
def test_unknown_products_and_tokens_that_do_not_fit_the_address_are_422_before_google(product_id, token):
    test_client, seen = _wire(_purchase(), rpc=GRANTED)

    assert _verify(test_client, product_id=product_id, token=token).status_code == 422
    assert _google(seen) == [] and _rpc_calls(seen) == []


def test_a_1000_character_token_is_accepted():
    test_client, _ = _wire(_purchase(), rpc=GRANTED)

    assert _verify(test_client, token="A" * 1000).status_code == 200


# V14 --------------------------------------------------------------------------------------------

def test_without_a_login_token_it_is_401_before_the_body_is_checked():
    test_client, seen = _wire(_purchase(), rpc=GRANTED)
    response = test_client.post("/billing/google/verify", json={"product_id": "heart_999"})

    assert response.status_code == 401
    assert seen == []


# S1 ---------------------------------------------------------------------------------------------

def test_status_before_any_purchase_offers_the_first_purchase_bonus():
    test_client, seen = _wire(purchases=[])
    response = test_client.get("/billing/status", headers=AUTH)

    assert response.status_code == 200
    assert response.json() == {
        "account_token": account_token(PROFILE_ID),
        "apple_account_token": apple_account_token(PROFILE_ID),
        "first_purchase_bonus": {"hearts": 50, "min_product_hearts": 100},
    }
    assert PROFILE_ID not in response.text
    (lookup,) = [r for r in seen if r.url.path == "/rest/v1/purchases"]
    assert lookup.url.params["profile_id"] == f"eq.{PROFILE_ID}"


def test_status_after_a_100_hearts_or_more_purchase_has_no_bonus():
    test_client, _ = _wire(purchases=[{"id": "p1", "heart_amount": 100}])
    body = test_client.get("/billing/status", headers=AUTH).json()

    assert body == {"account_token": account_token(PROFILE_ID), "apple_account_token": apple_account_token(PROFILE_ID),
                    "first_purchase_bonus": None}


def test_status_after_only_a_50_hearts_purchase_still_offers_the_bonus():
    # 사용자 결정 11-12: 50하트는 100하트가 아니다 — 100하트 이상을 산 적이 없으면 자격이 있다(DB 함수와 같은 규칙).
    test_client, _ = _wire(purchases=[{"id": "p1", "heart_amount": 50}])
    body = test_client.get("/billing/status", headers=AUTH).json()

    assert body["first_purchase_bonus"] == {"hearts": 50, "min_product_hearts": 100}


def test_status_counts_a_refunded_100_hearts_purchase_too():
    # 환불된 것도 센다 — 서버는 status 를 거르지 않는다(DB 의 지급 판정과 같은 규칙).
    test_client, seen = _wire(purchases=[{"id": "p1", "heart_amount": 100, "status": "refunded"}])

    assert test_client.get("/billing/status", headers=AUTH).json()["first_purchase_bonus"] is None
    (lookup,) = [r for r in seen if r.url.path == "/rest/v1/purchases"]
    assert "status" not in lookup.url.params


def test_status_needs_a_login():
    test_client, _ = _wire()

    assert test_client.get("/billing/status").status_code == 401


# R1 ---------------------------------------------------------------------------------------------

# e2e/area4_extra.py FORBIDDEN_HEART · PURCHASE_WORDS(E-HEART-49 · 51) — 하트 환급 · 선물 · 사는 이름이 붙은 서버 경로는
# 유료 카드 하나뿐이어야 한다.
HARNESS_WORDS = ("refund", "cashout", "transfer", "gift", "send_heart", "send-heart", "exchange", "heart_withdraw",
                 "heart-withdraw", "hearts/withdraw", "purchase", "buy", "unlock", "heart_store", "heart-store")


def test_billing_paths_avoid_the_harness_words():
    billing = [p for p in app.openapi()["paths"] if p.startswith(("/billing", "/batch/billing"))]

    assert sorted(billing) == ["/batch/billing-voided", "/billing/apple/notifications", "/billing/apple/verify",
                              "/billing/google/verify", "/billing/play/notifications", "/billing/status"]
    assert [p for p in billing if any(word in p.lower() for word in HARNESS_WORDS)] == []
