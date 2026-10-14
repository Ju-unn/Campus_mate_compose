"""아이폰 하트 구매 — POST /billing/apple/verify · POST /billing/apple/notifications · GET /billing/status 의 apple_account_token.

애플(App Store Server API)은 httpx.MockTransport 로 답을 정한다(실제 호출 없음). 애플이 서명하는 값은 시험 안에서 만든
인증서 체인(apple_world)으로 서명하고, 믿는 루트를 apple_root_ca 의존성으로 그 가짜 루트로 바꾼다.
DB 함수(grant_store_purchase · refund_store_purchase)의 답도 가짜다 — 함수 자체(보너스 · min(잔액, 합계) 회수)는 pgTAP 이 본다.
"""
import base64
import hashlib
import json
import logging
import pathlib
import subprocess
import sys
import uuid

import httpx
import pytest
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature
from fastapi.testclient import TestClient

from apple_world import CHAIN, NOW, make_chain, sign, tamper_signature, unsigned
from app.billing.apple import apple_account_token
from app.billing.apple_router import apple_root_ca
from app.core import errors
from app.core.deps import get_client, get_now, get_settings
from app.main import app
from app.settings import Settings

PROFILE_ID = "11111111-1111-1111-1111-111111111111"
# apple_account_token(PROFILE_ID) 를 글자 그대로 못박는다 — 만드는 규칙(네임스페이스)이 바뀌면 이미 산 거래가 전부 '다른 계정'이 된다.
APPLE_TOKEN = "8f06a0de-af89-53b5-ad89-be3d4097e993"
AUTH = {"Authorization": "Bearer valid-token"}
TX = "2000000812345678"
BUNDLE = "io.github.juunn.campusmate"
PRODUCTION = "api.storekit.itunes.apple.com"
SANDBOX = "api.storekit-sandbox.itunes.apple.com"
BOUGHT_AT_MS, BOUGHT_AT_ISO = 1791868800000, "2026-10-13T05:20:00+00:00"
GRANTED = {"result": "granted", "hearts": 100, "bonus_hearts": 50, "heart_balance": 150}

KEY_ID = "IAPKEY0001"
ISSUER_ID = "57246542-96fe-1a63-e053-0824d011072a"
# 애플이 내려 주는 앱 내 구입 키(.p8)와 같은 꼴(P-256 · PKCS#8 PEM). 시험마다 새로 만든 가짜 키다.
_IAP_KEY = ec.generate_private_key(ec.SECP256R1())
IAP_PEM = _IAP_KEY.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                 serialization.NoEncryption()).decode()
IAP_KEYS = {"apple_iap_key_id": KEY_ID, "apple_iap_issuer_id": ISSUER_ID, "apple_iap_private_key": IAP_PEM}
PEM_BODY = IAP_PEM.splitlines()[1]


def _settings(**changed) -> Settings:
    return Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test", **{**IAP_KEYS, **changed},
    )


@pytest.fixture(autouse=True)
def overrides():
    app.dependency_overrides[get_settings] = lambda: _settings()
    app.dependency_overrides[get_now] = lambda: NOW
    app.dependency_overrides[apple_root_ca] = lambda: CHAIN.root
    yield
    app.dependency_overrides.clear()


def _transaction(**changed) -> dict:
    """App Store 의 JWSTransactionDecodedPayload 꼴. 값을 None 으로 주면 그 칸을 뺀다."""
    base = {"transactionId": TX, "originalTransactionId": TX, "bundleId": BUNDLE, "productId": "heart_100",
            "purchaseDate": BOUGHT_AT_MS, "originalPurchaseDate": BOUGHT_AT_MS, "quantity": 1, "type": "Consumable",
            "inAppOwnershipType": "PURCHASED", "appAccountToken": APPLE_TOKEN, "environment": "Production",
            "signedDate": BOUGHT_AT_MS + 1000, "storefront": "KOR", "transactionReason": "PURCHASE",
            "price": 5700000, "currency": "KRW"}
    return {key: value for key, value in {**base, **changed}.items() if value is not None}


def _apple_answer(answer) -> httpx.Response:
    """str = 그 JWS 를 signedTransactionInfo 로 실은 200, dict = 그 본문 200, int = 그 상태 코드, 예외 = 던짐."""
    if isinstance(answer, Exception):
        raise answer
    if isinstance(answer, int):
        return httpx.Response(answer, json={"errorCode": answer * 10000, "errorMessage": "fake"})
    if isinstance(answer, str):
        return httpx.Response(200, json={"signedTransactionInfo": answer})
    return httpx.Response(200, json=answer)


def _wire(production=404, sandbox=404, rpc: dict | None = None, refund: dict | int | None = None,
          purchases: list | None = None, settings: Settings | None = None):
    """seen 에는 로그인 · 학생증 관문 밖 요청만 쌓인다."""
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if "/auth/v1/user" in str(request.url):
            return httpx.Response(200, json={"id": PROFILE_ID})
        # 관문 조회는 select 키로 가른다(reference_backend_test_mock_traps).
        if request.method == "GET" and "student_verification" in request.url.params.get("select", ""):
            return httpx.Response(200, json=[{"student_verification": "verified", "department": "컴공",
                                              "school_email_verified_at": "2026-10-01T00:00:00+00:00"}])
        seen.append(request)
        if request.url.host == PRODUCTION:
            return _apple_answer(production)
        if request.url.host == SANDBOX:
            return _apple_answer(sandbox)
        if request.url.path == "/rest/v1/rpc/grant_store_purchase":
            return httpx.Response(200, json=rpc)
        if request.url.path == "/rest/v1/rpc/refund_store_purchase":
            return httpx.Response(refund) if isinstance(refund, int) else httpx.Response(200, json=refund)
        if request.url.path == "/rest/v1/purchases" and request.method == "GET":
            return httpx.Response(200, json=purchases or [])
        return httpx.Response(404, json={"message": f"unexpected {request.method}"})

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    app.dependency_overrides[get_client] = lambda: client
    if settings is not None:
        app.dependency_overrides[get_settings] = lambda: settings
    return TestClient(app, raise_server_exceptions=False), seen


def _verify(test_client: TestClient, product_id: str = "heart_100", transaction_id: str = TX, headers: dict = AUTH):
    return test_client.post("/billing/apple/verify", headers=headers,
                            json={"product_id": product_id, "transaction_id": transaction_id})


def _apple(seen) -> list[httpx.Request]:
    return [r for r in seen if r.url.host in (PRODUCTION, SANDBOX)]


def _grants(seen) -> list[dict]:
    return [json.loads(r.content) for r in seen if r.url.path == "/rest/v1/rpc/grant_store_purchase"]


def _refunds(seen) -> list[dict]:
    return [json.loads(r.content) for r in seen if r.url.path == "/rest/v1/rpc/refund_store_purchase"]


def _b64url(part: str) -> bytes:
    return base64.urlsafe_b64decode(part + "=" * (-len(part) % 4))


# 확인 · 지급 ---------------------------------------------------------------------------------------

def test_a_production_purchase_is_looked_up_at_apple_and_granted_with_the_transaction_hash():
    test_client, seen = _wire(production=sign(_transaction()), rpc=GRANTED)
    response = _verify(test_client)

    assert response.status_code == 200
    assert response.json() == GRANTED
    assert [(r.method, r.url.host, r.url.path) for r in _apple(seen)] == [
        ("GET", PRODUCTION, f"/inApps/v1/transactions/{TX}")]
    assert _grants(seen) == [{
        "p_profile_id": PROFILE_ID, "p_store": "app_store", "p_product_id": "heart_100",
        "p_token_hash": hashlib.sha256(TX.encode()).hexdigest(), "p_order_id": TX,
        "p_purchased_at": BOUGHT_AT_ISO, "p_is_test": False,
    }]


def test_a_sandbox_purchase_is_looked_up_after_production_says_not_found_and_is_marked_as_test():
    # TestFlight · 심사 · 샌드박스 테스터의 거래는 운영 주소에 없다 — 애플 권장 순서대로 운영 → 샌드박스.
    test_client, seen = _wire(production=404, sandbox=sign(_transaction(environment="Sandbox")), rpc=GRANTED)
    response = _verify(test_client)

    assert response.status_code == 200 and response.json() == GRANTED
    assert [r.url.host for r in _apple(seen)] == [PRODUCTION, SANDBOX]
    assert _apple(seen)[1].url.path == f"/inApps/v1/transactions/{TX}"
    assert [g["p_is_test"] for g in _grants(seen)] == [True]


@pytest.mark.parametrize("production, sandbox, asked", [
    (404, 404, [PRODUCTION, SANDBOX]),
    # 400 = 애플이 거래 번호 꼴을 거절(InvalidTransactionId) — 샌드박스에 물어도 같다.
    (400, 404, [PRODUCTION]),
    (404, 400, [PRODUCTION, SANDBOX]),
    # 거래 번호 꼴은 환경과 상관없다 — 운영이 401 이었어도 샌드박스의 400 은 '없는 거래'다.
    (401, 400, [PRODUCTION, SANDBOX]),
])
def test_a_transaction_apple_does_not_know_is_invalid(production, sandbox, asked):
    test_client, seen = _wire(production=production, sandbox=sandbox, rpc=GRANTED)
    response = _verify(test_client)

    assert response.status_code == 422
    assert response.json() == {"detail": errors.PURCHASE_INVALID, "code": "purchase_invalid"}
    assert [r.url.host for r in _apple(seen)] == asked
    assert _grants(seen) == []


def test_the_same_transaction_again_is_answered_without_new_hearts():
    already = {**GRANTED, "result": "already_granted"}
    test_client, seen = _wire(production=sign(_transaction()), rpc=already)
    response = _verify(test_client)

    assert response.status_code == 200 and response.json() == already
    assert len(_grants(seen)) == 1


def test_a_transaction_another_account_already_received_is_409():
    test_client, _ = _wire(production=sign(_transaction()), rpc={"result": "token_used"})
    response = _verify(test_client)

    assert response.status_code == 409
    assert response.json() == {"detail": errors.PURCHASE_TOKEN_USED, "code": "purchase_token_used"}


@pytest.mark.parametrize("changed", [
    # 50하트를 사고 800하트로 받으려는 요청 — 지급량은 요청의 상품으로 정해서 애플의 상품과 같아야 한다.
    {"productId": "heart_50"},
    {"bundleId": "com.someone.else"},
    {"bundleId": None},
    # 환불된 거래라도 우리 거래가 아니면(번들 · 상품이 다르면) 환불 코드가 아니다 — 앱은 purchase_revoked 에서만 거래를 끝낸다.
    {"revocationDate": BOUGHT_AT_MS + 60_000, "bundleId": "com.someone.else"},
    {"revocationDate": BOUGHT_AT_MS + 60_000, "productId": "heart_50"},
    {"type": "Non-Consumable"},
    {"type": None},
    {"inAppOwnershipType": "FAMILY_SHARED"},
    {"quantity": 2},
    {"transactionId": "2000000899999999"},
    {"environment": "Xcode"},
    {"environment": None},
    {"purchaseDate": None},
])
def test_a_transaction_apple_does_not_vouch_for_as_this_purchase_is_invalid(changed):
    test_client, seen = _wire(production=sign(_transaction(**changed)), rpc=GRANTED)
    response = _verify(test_client)

    assert response.status_code == 422
    assert response.json() == {"detail": errors.PURCHASE_INVALID, "code": "purchase_invalid"}
    assert _grants(seen) == []


@pytest.mark.parametrize("token", [APPLE_TOKEN, apple_account_token("22222222-2222-2222-2222-222222222222")])
def test_a_refunded_transaction_is_422_purchase_revoked_whatever_account_it_carries(token):
    # 환불된(revocationDate) 거래는 다시 보내도 하트가 들어갈 길이 없다 — 따로 된 code 를 받은 앱만 거래를 끝낸다(하트 없음).
    # 남겨 두면 같은 Apple ID 가 같은 상품을 다시 못 산다(storekit_duplicate_product_object). 계정 대조보다 먼저 본다 —
    # 다른 계정의 환불 거래도 결제한 계정으로 로그인해 받을 하트가 없다.
    test_client, seen = _wire(production=sign(_transaction(revocationDate=BOUGHT_AT_MS + 60_000, revocationReason=0,
                                                           appAccountToken=token)), rpc=GRANTED)
    response = _verify(test_client)

    assert response.status_code == 422
    assert response.json() == {"detail": errors.PURCHASE_REVOKED, "code": "purchase_revoked"}
    assert _grants(seen) == []


@pytest.mark.parametrize("token", ["00000000-0000-0000-0000-000000000000", "not-a-uuid", None,
                                   apple_account_token("22222222-2222-2222-2222-222222222222")])
def test_a_purchase_made_for_another_account_is_409(token):
    test_client, seen = _wire(production=sign(_transaction(appAccountToken=token)), rpc=GRANTED)
    response = _verify(test_client)

    assert response.status_code == 409
    assert response.json() == {"detail": errors.PURCHASE_OTHER_ACCOUNT, "code": "purchase_other_account"}
    assert _grants(seen) == []


def test_the_account_token_matches_whatever_letter_case_apple_writes_it_in():
    # Swift 의 UUID.uuidString 은 대문자다 — 같은 UUID 면 같은 사람이다.
    test_client, seen = _wire(production=sign(_transaction(appAccountToken=APPLE_TOKEN.upper())), rpc=GRANTED)

    assert _verify(test_client).status_code == 200
    assert len(_grants(seen)) == 1


@pytest.mark.parametrize("production, sandbox", [
    (500, 404), (503, 404), (429, 404), (401, 404), (403, 404), (httpx.ConnectTimeout("slow"), 404),
    (404, 500), (404, 429), (404, httpx.ReadTimeout("slow")),
])
def test_apple_outage_is_503_and_nothing_is_granted(production, sandbox):
    test_client, seen = _wire(production=production, sandbox=sandbox, rpc=GRANTED)
    response = _verify(test_client)

    assert response.status_code == 503
    assert response.json() == {"detail": errors.BILLING_UNAVAILABLE, "code": "billing_unavailable"}
    assert _grants(seen) == []


# 운영 401 → 샌드박스. 같은 키 · 발급자 · 번들로 운영 주소만 401 을 준 적이 있다(2026-10-14 실측 — 개발자 멤버십 비활성 중,
# 샌드박스는 404 로 인증을 넘었다). 운영 401 은 샌드박스에 한 번 더 묻는다. 403 · 429 · 5xx · 시간 초과는 넘기지 않는다 —
# 일시 장애를 샌드박스 거래로 오인하지 않게. 그 자리의 샌드박스 답은 진짜 거래(SANDBOX_TX)라 잘못 넘기면 200 이 되어 드러난다.
SANDBOX_TX = sign(_transaction(environment="Sandbox"))


def test_a_sandbox_purchase_is_granted_as_test_when_production_answers_401():
    test_client, seen = _wire(production=401, sandbox=SANDBOX_TX, rpc=GRANTED)
    response = _verify(test_client)

    assert response.status_code == 200 and response.json() == GRANTED
    assert [r.url.host for r in _apple(seen)] == [PRODUCTION, SANDBOX]
    assert _apple(seen)[1].url.path == f"/inApps/v1/transactions/{TX}"
    assert [g["p_is_test"] for g in _grants(seen)] == [True]


@pytest.mark.parametrize("production, sandbox, asked", [
    # 운영 401 뒤 샌드박스도 막히면 기존대로 503.
    (401, 401, [PRODUCTION, SANDBOX]),
    (401, 403, [PRODUCTION, SANDBOX]),
    (401, 429, [PRODUCTION, SANDBOX]),
    (401, 500, [PRODUCTION, SANDBOX]),
    (401, httpx.ReadTimeout("slow"), [PRODUCTION, SANDBOX]),
    # 운영 401 뒤 샌드박스에 없으면 운영 거래인지 모르는 채다 — '없는 거래'(422)가 아니라 503(앱이 나중에 다시 보낸다).
    (401, 404, [PRODUCTION, SANDBOX]),
    (403, SANDBOX_TX, [PRODUCTION]),
    (429, SANDBOX_TX, [PRODUCTION]),
    (500, SANDBOX_TX, [PRODUCTION]),
    (503, SANDBOX_TX, [PRODUCTION]),
    (httpx.ConnectTimeout("slow"), SANDBOX_TX, [PRODUCTION]),
], ids=["401-401", "401-403", "401-429", "401-500", "401-timeout", "401-404",
        "403-stop", "429-stop", "500-stop", "503-stop", "timeout-stop"])
def test_only_a_production_401_or_404_moves_on_to_sandbox_and_an_outage_stays_503(production, sandbox, asked):
    test_client, seen = _wire(production=production, sandbox=sandbox, rpc=GRANTED)
    response = _verify(test_client)

    assert response.status_code == 503
    assert response.json() == {"detail": errors.BILLING_UNAVAILABLE, "code": "billing_unavailable"}
    assert [r.url.host for r in _apple(seen)] == asked
    assert _grants(seen) == []


@pytest.mark.parametrize("production, sandbox, trail", [
    (401, 401, "production:401 sandbox:401"),
    (401, 404, "production:401 sandbox:404"),
    (404, 503, "production:404 sandbox:503"),
    (403, SANDBOX_TX, "production:403"),
    (httpx.ConnectTimeout("slow"), 404, "production:transport"),
    (404, httpx.ReadTimeout("slow"), "production:404 sandbox:transport"),
], ids=["401-401", "401-404", "404-503", "403-stop", "timeout", "404-timeout"])
def test_an_outage_log_names_each_environment_asked_with_its_status_only(production, sandbox, trail, caplog):
    caplog.set_level(logging.DEBUG)
    test_client, _ = _wire(production=production, sandbox=sandbox, rpc=GRANTED)
    _verify(test_client)

    (line,) = [r.getMessage() for r in caplog.records if "애플 거래 조회 실패" in r.getMessage()]
    assert line.endswith(f"status={trail}")


def test_moving_on_from_a_production_401_is_warned_with_the_status_only(caplog):
    # 멤버십이 돌아온 뒤에도 운영이 401 이면 실제 구매가 503 이 된다 — 샌드박스로 넘어간 것 자체를 경고로 남긴다.
    caplog.set_level(logging.DEBUG)
    test_client, _ = _wire(production=401, sandbox=SANDBOX_TX, rpc=GRANTED)

    assert _verify(test_client).status_code == 200
    assert [r.getMessage() for r in caplog.records if r.levelno == logging.WARNING] == [
        "애플 거래 조회 production:401 — 샌드박스에 한 번 더 묻는다"]


@pytest.mark.parametrize("answer", [
    tamper_signature(sign(_transaction())),
    sign(_transaction(), make_chain()),
    sign(_transaction(), make_chain(root=CHAIN, leaf_oid=False)),
    unsigned(_transaction()),
    "not-a-jws",
    {"unexpected": "shape"},
], ids=["tampered", "other_root", "leaf_without_oid", "alg_none", "not_jws", "no_signed_info"])
def test_an_answer_that_is_not_signed_by_apple_grants_nothing_and_is_503(answer):
    # 애플 주소에서 받은 답의 서명이 틀리면 우리 검증(루트 교체 등) 쪽 문제일 가능성이 크다 — 앱이 나중에 다시 보내게 503.
    test_client, seen = _wire(production=answer, rpc=GRANTED)
    response = _verify(test_client)

    assert response.status_code == 503
    assert response.json() == {"detail": errors.BILLING_UNAVAILABLE, "code": "billing_unavailable"}
    assert _grants(seen) == []


@pytest.mark.parametrize("missing", ["apple_iap_key_id", "apple_iap_issuer_id", "apple_iap_private_key"])
def test_without_the_in_app_purchase_key_it_is_503_before_asking_apple(missing):
    test_client, seen = _wire(production=sign(_transaction()), rpc=GRANTED, settings=_settings(**{missing: ""}))
    response = _verify(test_client)

    assert response.status_code == 503
    assert response.json() == {"detail": errors.BILLING_UNAVAILABLE, "code": "apple_not_configured"}
    assert seen == []


def test_a_broken_private_key_is_503_and_its_text_is_not_logged(caplog):
    caplog.set_level(logging.DEBUG)
    broken = "-----BEGIN PRIVATE KEY-----\nbrokenkeymaterial\n-----END PRIVATE KEY-----"
    test_client, seen = _wire(production=sign(_transaction()), rpc=GRANTED,
                              settings=_settings(apple_iap_private_key=broken))
    response = _verify(test_client)

    assert response.status_code == 503
    assert response.json()["code"] == "billing_unavailable"
    assert _apple(seen) == [] and _grants(seen) == []
    assert "brokenkeymaterial" not in caplog.text


def test_apple_is_asked_with_a_short_es256_token_signed_by_the_in_app_purchase_key():
    test_client, seen = _wire(production=sign(_transaction()), rpc=GRANTED)
    _verify(test_client)

    (request,) = _apple(seen)
    scheme, token = request.headers["Authorization"].split(" ")
    head, body, signature = token.split(".")
    claims = json.loads(_b64url(body))
    assert scheme == "Bearer"
    assert json.loads(_b64url(head)) == {"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}
    assert {key: claims[key] for key in ("iss", "aud", "bid", "iat")} == {
        "iss": ISSUER_ID, "aud": "appstoreconnect-v1", "bid": BUNDLE, "iat": int(NOW.timestamp())}
    # 애플 상한은 60분 — 그보다 짧게.
    assert 0 < claims["exp"] - claims["iat"] < 3600
    raw = _b64url(signature)
    der = encode_dss_signature(int.from_bytes(raw[:32], "big"), int.from_bytes(raw[32:], "big"))
    _IAP_KEY.public_key().verify(der, f"{head}.{body}".encode(), ec.ECDSA(hashes.SHA256()))


@pytest.mark.parametrize("product_id, transaction_id", [
    ("heart_999", TX), ("heart_100", ""), ("heart_100", "abc"), ("heart_100", "1/2"), ("heart_100", " 123"),
    ("heart_100", "../../notifications"), ("heart_100", "1" * 65),
])
def test_unknown_products_and_transaction_ids_that_do_not_fit_the_address_are_422_before_apple(product_id,
                                                                                                transaction_id):
    test_client, seen = _wire(production=sign(_transaction()), rpc=GRANTED)

    assert _verify(test_client, product_id=product_id, transaction_id=transaction_id).status_code == 422
    assert _apple(seen) == [] and _grants(seen) == []


def test_without_a_login_token_it_is_401_before_anything():
    test_client, seen = _wire(production=sign(_transaction()), rpc=GRANTED)
    response = test_client.post("/billing/apple/verify", json={"product_id": "heart_999"})

    assert response.status_code == 401
    assert seen == []


@pytest.mark.parametrize("rpc", [{"result": "unknown_product"}, {"result": "surprise"}, {}])
def test_a_grant_answer_outside_the_contract_is_500(rpc):
    test_client, _ = _wire(production=sign(_transaction()), rpc=rpc)

    assert _verify(test_client).status_code == 500


@pytest.mark.parametrize("production, sandbox, rpc", [
    (sign(_transaction()), 404, GRANTED),
    (500, 404, None),
    (404, 404, None),
    (sign(_transaction(appAccountToken=None)), 404, None),
    (sign(_transaction()), 404, {"result": "token_used"}),
    (tamper_signature(sign(_transaction())), 404, None),
    (sign(_transaction(revocationDate=BOUGHT_AT_MS)), 404, None),
    (401, SANDBOX_TX, GRANTED),
    (401, 401, None),
], ids=["granted", "outage", "not_found", "other_account", "token_used", "tampered", "revoked",
        "production_401_then_sandbox", "both_401"])
def test_verify_logs_never_contain_the_transaction_id_the_jws_or_our_token(production, sandbox, rpc, caplog):
    caplog.set_level(logging.DEBUG)
    test_client, seen = _wire(production=production, sandbox=sandbox, rpc=rpc)
    _verify(test_client)

    secrets = [TX, PEM_BODY, *(r.headers["Authorization"].split(" ")[1] for r in _apple(seen))]
    for answer in (production, sandbox):
        if isinstance(answer, str):
            secrets += answer.split(".")
    for secret in secrets:
        assert secret not in caplog.text, secret


# 상점 상태 ------------------------------------------------------------------------------------------

def test_status_gives_a_uuid_apple_account_token_that_is_not_the_profile_id():
    test_client, _ = _wire()
    response = test_client.get("/billing/status", headers=AUTH)

    assert response.status_code == 200
    token = response.json()["apple_account_token"]
    assert token == APPLE_TOKEN
    # appAccountToken 은 UUID 여야 한다(애플). profile_id 에서 결정적으로 만든 UUIDv5.
    assert str(uuid.UUID(token)) == token and uuid.UUID(token).version == 5
    assert PROFILE_ID not in response.text


def test_the_apple_account_token_is_the_same_every_time_and_differs_per_person():
    assert apple_account_token(PROFILE_ID) == apple_account_token(uuid.UUID(PROFILE_ID)) == APPLE_TOKEN
    assert apple_account_token("22222222-2222-2222-2222-222222222222") != APPLE_TOKEN


# 환불 알림(App Store Server Notifications V2) ---------------------------------------------------------

def _payload(kind: str = "REFUND", transaction: dict | None = None, *, environment: str = "Production",
             **data_changed) -> dict:
    """responseBodyV2DecodedPayload 꼴. data 의 칸을 None 으로 주면 뺀다."""
    data = {"appAppleId": 1234567890, "bundleId": BUNDLE, "bundleVersion": "1.0.0", "environment": environment,
            "signedTransactionInfo": sign(transaction or _transaction(environment=environment))}
    data = {key: value for key, value in {**data, **data_changed}.items() if value is not None}
    return {"notificationType": kind, "notificationUUID": "002e14d5-51f5-4503-b5a8-c3a1af68eb20",
            "data": data, "version": "2.0", "signedDate": BOUGHT_AT_MS + 86_400_000}


def _notify(test_client: TestClient, signed_payload):
    # 애플은 우리 로그인 토큰이 없다 — Authorization 없이 부른다.
    return test_client.post("/billing/apple/notifications", json={"signedPayload": signed_payload})


REFUNDED = {"result": "refunded", "profile_id": PROFILE_ID, "clawed_back": 150, "shortfall": 0}


@pytest.mark.parametrize("kind", ["REFUND", "REVOKE"])
def test_a_refund_notification_claws_back_the_purchase_by_its_transaction_hash(kind):
    test_client, seen = _wire(refund=REFUNDED)
    response = _notify(test_client, sign(_payload(kind)))

    assert response.status_code == 200
    assert response.json() == {"result": "refunded"}
    assert _refunds(seen) == [{"p_store": "app_store", "p_token_hash": hashlib.sha256(TX.encode()).hexdigest()}]
    # 알림 내용은 서명 체인으로 믿는다 — 애플에 다시 묻지 않는다.
    assert _apple(seen) == []


def test_a_sandbox_refund_notification_claws_back_the_test_purchase():
    test_client, seen = _wire(refund=REFUNDED)

    assert _notify(test_client, sign(_payload(environment="Sandbox"))).status_code == 200
    assert len(_refunds(seen)) == 1


@pytest.mark.parametrize("result", ["already_refunded", "unknown"])
def test_a_refund_already_handled_or_never_granted_is_200(result):
    # 애플은 200 이 아니면 다시 보낸다 — 이미 회수했거나 우리가 지급한 적 없는 거래는 할 일이 없다(멱등).
    test_client, seen = _wire(refund={"result": result})
    response = _notify(test_client, sign(_payload()))

    assert response.status_code == 200 and response.json() == {"result": result}
    assert len(_refunds(seen)) == 1


def test_a_shortfall_warns_with_the_number_but_without_the_profile_or_transaction(caplog):
    # 환불 전에 이미 쓴 하트는 회수하지 못한다(결정 I-1) — 남은 만큼만 회수한 뒤 모자람을 숫자로 남긴다.
    caplog.set_level(logging.DEBUG)
    test_client, _ = _wire(refund={"result": "refunded", "profile_id": PROFILE_ID, "clawed_back": 30, "shortfall": 120})

    assert _notify(test_client, sign(_payload())).status_code == 200
    (warning,) = [r for r in caplog.records if r.levelno == logging.WARNING]
    assert "shortfall=120" in warning.getMessage()
    assert PROFILE_ID not in caplog.text and TX not in caplog.text


@pytest.mark.parametrize("make", [
    lambda: tamper_signature(sign(_payload())),
    lambda: unsigned(_payload()),
    lambda: sign(_payload(), alg="HS256"),
    lambda: sign(_payload(), make_chain()),
    lambda: sign(_payload(), make_chain(root=CHAIN, intermediate_oid=False)),
    lambda: "not-a-jws",
], ids=["tampered", "alg_none", "hs256", "other_root", "intermediate_without_oid", "not_jws"])
def test_a_notification_not_signed_by_apple_is_400_and_touches_nothing(make):
    test_client, seen = _wire(refund=REFUNDED)
    response = _notify(test_client, make())

    assert response.status_code == 400
    assert seen == []


@pytest.mark.parametrize("signed_transaction", [
    tamper_signature(sign(_transaction())),
    sign(_transaction(), make_chain()),
    "not-a-jws",
    None,
], ids=["tampered", "other_root", "not_jws", "missing"])
def test_a_refund_whose_transaction_is_not_signed_by_apple_is_400(signed_transaction):
    test_client, seen = _wire(refund=REFUNDED)
    payload = _payload()
    if signed_transaction is None:
        del payload["data"]["signedTransactionInfo"]
    else:
        payload["data"]["signedTransactionInfo"] = signed_transaction
    response = _notify(test_client, sign(payload))

    assert response.status_code == 400
    assert seen == []


@pytest.mark.parametrize("notified, transaction", [("Production", "Sandbox"), ("Sandbox", "Production")])
def test_a_refund_whose_environment_differs_from_its_transaction_is_400(notified, transaction):
    test_client, seen = _wire(refund=REFUNDED)
    payload = _payload(transaction=_transaction(environment=transaction), environment=notified)
    response = _notify(test_client, sign(payload))

    assert response.status_code == 400
    assert seen == []


@pytest.mark.parametrize("payload", [
    _payload(bundleId="com.someone.else"),
    _payload(transaction=_transaction(bundleId="com.someone.else")),
], ids=["notification_bundle", "transaction_bundle"])
def test_a_notification_for_another_app_is_400(payload):
    test_client, seen = _wire(refund=REFUNDED)

    assert _notify(test_client, sign(payload)).status_code == 400
    assert seen == []


def test_the_test_notification_is_200_and_touches_nothing():
    test_client, seen = _wire(refund=REFUNDED)
    payload = {"notificationType": "TEST", "notificationUUID": "3e3f1a7c-0000-4000-8000-000000000000",
               "data": {"bundleId": BUNDLE, "environment": "Sandbox"}, "version": "2.0", "signedDate": BOUGHT_AT_MS}
    response = _notify(test_client, sign(payload))

    assert response.status_code == 200
    assert seen == []


@pytest.mark.parametrize("kind", ["CONSUMPTION_REQUEST", "REFUND_DECLINED", "REFUND_REVERSED", "ONE_TIME_CHARGE",
                                  "SURPRISE"])
def test_other_notification_types_are_200_and_touch_nothing(kind):
    test_client, seen = _wire(refund=REFUNDED)

    assert _notify(test_client, sign(_payload(kind))).status_code == 200
    assert seen == []


def test_a_reversed_refund_is_left_for_the_operator_with_a_warning(caplog):
    # 환불 번복은 하트를 되돌리지 않는다(사용자 미결 A-6) — 운영자가 손으로 처리하게 경고만 남긴다.
    caplog.set_level(logging.DEBUG)
    test_client, seen = _wire(refund=REFUNDED)

    assert _notify(test_client, sign(_payload("REFUND_REVERSED"))).status_code == 200
    assert any(r.levelno == logging.WARNING and "REFUND_REVERSED" in r.getMessage() for r in caplog.records)
    assert seen == [] and TX not in caplog.text


@pytest.mark.parametrize("body", [{}, {"signedPayload": ""}, {"signedPayload": 123}, {"other": "x"}])
def test_a_body_without_a_signed_payload_is_422(body):
    test_client, seen = _wire(refund=REFUNDED)

    assert test_client.post("/billing/apple/notifications", json=body).status_code == 422
    assert seen == []


def test_notifications_work_without_the_in_app_purchase_key():
    # 알림은 애플에 묻지 않는다 — .p8 이 아직 없어도 환불 회수는 돈다.
    empty = {key: "" for key in IAP_KEYS}
    test_client, seen = _wire(refund=REFUNDED, settings=_settings(**empty))

    assert _notify(test_client, sign(_payload())).status_code == 200
    assert len(_refunds(seen)) == 1


def test_a_database_failure_is_500_so_apple_sends_it_again():
    test_client, _ = _wire(refund=500)

    assert _notify(test_client, sign(_payload())).status_code == 500


@pytest.mark.parametrize("kind, refund", [("REFUND", REFUNDED), ("REFUND", {"result": "unknown"}), ("TEST", None),
                                          ("CONSUMPTION_REQUEST", None)])
def test_notification_logs_show_the_type_and_a_short_transaction_prefix_only(kind, refund, caplog):
    caplog.set_level(logging.INFO)
    signed = sign(_payload(kind))
    test_client, _ = _wire(refund=refund)
    _notify(test_client, signed)

    infos = [r.getMessage() for r in caplog.records if r.levelno == logging.INFO and "애플 알림" in r.getMessage()]
    assert len(infos) == 1 and kind in infos[0]
    for secret in (TX, PROFILE_ID, *signed.split(".")):
        assert secret not in caplog.text, secret
    if kind == "REFUND":
        assert f"tx={TX[:6]}" in infos[0] and f"result={refund['result']}" in infos[0]


def test_apple_info_logs_reach_stderr_in_a_fresh_process():
    """운영(uvicorn)은 루트 로거에 핸들러가 없고 수준이 WARNING 이라 INFO 가 버려진다. 새 프로세스에서 실제로 찍히는지 본다."""
    code = "from app.billing import apple_router; apple_router.logger.info('apple-probe')"
    backend = pathlib.Path(__file__).resolve().parents[2]
    done = subprocess.run([sys.executable, "-c", code], cwd=backend, capture_output=True, text=True, timeout=60)
    assert "apple-probe" in done.stderr, done.stderr
