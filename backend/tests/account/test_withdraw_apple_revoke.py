"""탈퇴 때 애플 토큰 철회(App Store 5.1.1(v), app/account/social_unlink.py). 진짜 애플은 부르지 않는다 — 가짜 서버로만 본다.

우리는 signInWithIdToken 으로 로그인해 refresh_token 이 없다. 그래서 앱이 탈퇴 직전에 애플 창을 한 번 더 띄워
일회용 authorizationCode 를 본문(apple_authorization_code)에 싣고, 서버가 그 코드를 refresh_token 으로 바꾼 뒤 바로 철회한다.
토큰은 저장하지 않는다. 실패해도 탈퇴는 그대로 끝나고 단계 이름만 경고로 남는다(코드 · 토큰 · 키는 로그에 없다).
"""
import base64
import importlib
import json
import logging
import re
import time
from urllib.parse import parse_qs

import google.auth.crypt
import httpx
import pytest
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature

from account_world import APPLE_ACCESS_TOKEN, APPLE_REFRESH_TOKEN, AUTH, ME
from app.account import social_unlink
from app.core.deps import get_client
from app.main import app
from app.settings import Settings

TEAM_ID = "TEAM000001"
KEY_ID = "KEY0000001"
CLIENT_ID = "io.github.juunn.campusmate"  # 네이티브 앱 흐름이라 client_id = 번들 ID
CODE = "c0de-from-the-apple-sheet"
# 애플이 내려 주는 .p8 과 같은 꼴(P-256 · PKCS#8 PEM). 시험마다 새로 만든 가짜 키다.
_KEY = ec.generate_private_key(ec.SECP256R1())
PRIVATE_KEY = _KEY.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                 serialization.NoEncryption()).decode()
APPLE_KEYS = {"apple_team_id": TEAM_ID, "apple_key_id": KEY_ID, "apple_private_key": PRIVATE_KEY}
WITH_CODE = {"apple_authorization_code": CODE}


def _form(request) -> dict:
    return {k: v[0] for k, v in parse_qs(request.content.decode()).items()}


def _warned_steps(caplog) -> list[str]:
    """router 가 남긴 `탈퇴 뒤 정리 실패 step=<이름>` 경고의 단계 이름들."""
    return [m.group(1) for r in caplog.records if r.levelno == logging.WARNING
            if (m := re.search(r"step=(\S+)", r.getMessage()))]


def _segment(part: str) -> bytes:
    return base64.urlsafe_b64decode(part + "=" * (-len(part) % 4))


@pytest.fixture
def apple_user(world):
    world.identities = [{"provider": "apple", "identity_data": {"sub": "000123.abc.0456"}}]
    world.settings_overrides = dict(APPLE_KEYS)
    return world


def test_the_code_is_exchanged_then_the_refresh_token_is_revoked(client, apple_user):
    response = client.post("/account/withdraw", headers=AUTH, json=WITH_CODE)

    assert response.status_code == 200
    exchange, revoke = apple_user.apple_requests
    assert str(exchange.url) == "https://appleid.apple.com/auth/token"
    assert exchange.headers["content-type"].startswith("application/x-www-form-urlencoded")
    sent = _form(exchange)
    assert sent.pop("client_secret")
    assert sent == {"client_id": CLIENT_ID, "code": CODE, "grant_type": "authorization_code"}
    assert str(revoke.url) == "https://appleid.apple.com/auth/revoke"
    assert revoke.headers["content-type"].startswith("application/x-www-form-urlencoded")
    sent = _form(revoke)
    assert sent.pop("client_secret")
    assert sent == {"client_id": CLIENT_ID, "token": APPLE_REFRESH_TOKEN, "token_type_hint": "refresh_token"}


def test_the_client_secret_is_a_short_lived_es256_jwt_signed_with_the_key(client, apple_user):
    before = int(time.time())
    client.post("/account/withdraw", headers=AUTH, json=WITH_CODE)
    after = int(time.time())

    assert len(apple_user.apple_requests) == 2  # 코드 교환 · 철회 둘 다 같은 꼴의 비밀을 싣는다
    for request in apple_user.apple_requests:
        header, payload, signature = _form(request)["client_secret"].split(".")
        assert json.loads(_segment(header)) == {"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}
        claims = json.loads(_segment(payload))
        assert claims["iss"] == TEAM_ID
        assert claims["sub"] == CLIENT_ID
        assert claims["aud"] == "https://appleid.apple.com"
        assert before <= claims["iat"] <= after
        # 짧게 — 두 요청을 보낼 동안만 쓴다(애플 상한은 6개월).
        assert claims["exp"] - claims["iat"] == 300
        raw = _segment(signature)
        assert len(raw) == 64  # JWS ES256 은 DER 이 아니라 r ‖ s 32바이트씩이다
        der = encode_dss_signature(int.from_bytes(raw[:32], "big"), int.from_bytes(raw[32:], "big"))
        # 서명이 틀리면 InvalidSignature 로 실패한다.
        _KEY.public_key().verify(der, f"{header}.{payload}".encode(), ec.ECDSA(hashes.SHA256()))


def test_the_revocation_happens_after_the_db_function(client, apple_user):
    """철회는 정리 단계다 — 탈퇴(상태 변경)가 먼저 끝나야 한다."""
    client.post("/account/withdraw", headers=AUTH, json=WITH_CODE)

    paths = [r.url.path for r in apple_user.requests
             if r.url.path in ("/rest/v1/rpc/withdraw_account", "/auth/token", "/auth/revoke")]
    assert paths == ["/rest/v1/rpc/withdraw_account", "/auth/token", "/auth/revoke"]


@pytest.mark.parametrize("missing", ["apple_team_id", "apple_key_id", "apple_private_key"])
def test_any_missing_key_setting_skips_apple(client, apple_user, missing):
    apple_user.settings_overrides[missing] = ""

    response = client.post("/account/withdraw", headers=AUTH, json=WITH_CODE)

    assert response.status_code == 200
    assert apple_user.apple_requests == []


@pytest.mark.parametrize("body", [None, {}, {"apple_authorization_code": None}, {"apple_authorization_code": ""}])
def test_no_code_skips_apple(client, apple_user, body):
    """카카오 · 구글 사용자, 애플 창을 닫은 애플 사용자, 본문 없이 부르는 E2E 하네스."""
    response = client.post("/account/withdraw", headers=AUTH, json=body)

    assert response.status_code == 200
    assert apple_user.profiles[ME]["status"] == "withdrawn"
    assert apple_user.apple_requests == []
    assert len(apple_user.calls("POST", "/auth/v1/logout")) == 1


@pytest.mark.parametrize("status", [400, 500])
def test_a_failed_code_exchange_does_not_stop_the_withdrawal(client, apple_user, caplog, status):
    apple_user.apple_token_status = status

    with caplog.at_level(logging.DEBUG):
        response = client.post("/account/withdraw", headers=AUTH, json=WITH_CODE)

    assert response.status_code == 200
    assert apple_user.profiles[ME]["status"] == "withdrawn"
    assert [r.url.path for r in apple_user.apple_requests] == ["/auth/token"]
    assert len(apple_user.calls("POST", "/auth/v1/logout")) == 1
    assert _warned_steps(caplog) == ["apple_token_exchange"]


@pytest.mark.parametrize("status", [400, 503])
def test_a_failed_revocation_does_not_stop_the_withdrawal(client, apple_user, caplog, status):
    apple_user.apple_revoke_status = status

    with caplog.at_level(logging.DEBUG):
        response = client.post("/account/withdraw", headers=AUTH, json=WITH_CODE)

    assert response.status_code == 200
    assert len(apple_user.calls("POST", "/auth/v1/logout")) == 1
    assert _warned_steps(caplog) == ["apple_revoke"]


def test_apple_unreachable_does_not_stop_the_withdrawal(client, apple_user):
    apple_user.apple_unreachable = True

    response = client.post("/account/withdraw", headers=AUTH, json=WITH_CODE)

    assert response.status_code == 200
    assert len(apple_user.calls("POST", "/auth/v1/logout")) == 1


def test_a_broken_private_key_does_not_stop_the_withdrawal(client, apple_user, caplog):
    apple_user.settings_overrides["apple_private_key"] = "-----BEGIN PRIVATE KEY-----\nbroken\n-----END PRIVATE KEY-----"

    with caplog.at_level(logging.DEBUG):
        response = client.post("/account/withdraw", headers=AUTH, json=WITH_CODE)

    assert response.status_code == 200
    assert apple_user.apple_requests == []
    assert len(apple_user.calls("POST", "/auth/v1/logout")) == 1
    assert _warned_steps(caplog) == ["apple_token_exchange"]
    assert "broken" not in caplog.text


def test_without_the_es256_signer_the_module_still_imports(monkeypatch):
    """cryptography 가 빠진 google-auth 에는 ES256Signer 가 없다 — 그래도 서버 전체가 뜬다(애플 단계만 실패)."""
    monkeypatch.delattr(google.auth.crypt, "ES256Signer")

    importlib.reload(social_unlink)  # 맨 위에서 가져오면 여기서 ImportError


def test_without_the_es256_signer_the_withdrawal_ends_with_only_a_warning(client, apple_user, caplog, monkeypatch):
    monkeypatch.delattr(google.auth.crypt, "ES256Signer")

    with caplog.at_level(logging.WARNING):
        response = client.post("/account/withdraw", headers=AUTH, json=WITH_CODE)

    assert response.status_code == 200
    assert apple_user.profiles[ME]["status"] == "withdrawn"
    assert apple_user.apple_requests == []
    assert len(apple_user.calls("POST", "/auth/v1/logout")) == 1
    assert _warned_steps(caplog) == ["apple_token_exchange"]


def test_both_apple_calls_carry_their_own_5_second_timeout(client, apple_user):
    """앱 전체가 나눠 쓰는 클라이언트 설정과 상관없이 애플 두 요청은 5초에서 끊는다."""
    app.dependency_overrides[get_client] = lambda: httpx.AsyncClient(
        transport=httpx.MockTransport(apple_user.handle), timeout=None)

    client.post("/account/withdraw", headers=AUTH, json=WITH_CODE)

    assert [r.url.path for r in apple_user.apple_requests] == ["/auth/token", "/auth/revoke"]
    for request in apple_user.apple_requests:
        assert request.extensions["timeout"] == {"connect": 5.0, "read": 5.0, "write": 5.0, "pool": 5.0}


@pytest.mark.parametrize("trouble", ["ok", "token_500", "revoke_500", "unreachable"])
def test_no_secret_reaches_any_log(client, apple_user, caplog, trouble):
    if trouble == "token_500":
        apple_user.apple_token_status = 500
    if trouble == "revoke_500":
        apple_user.apple_revoke_status = 500
    if trouble == "unreachable":
        apple_user.apple_unreachable = True

    with caplog.at_level(logging.DEBUG):
        client.post("/account/withdraw", headers=AUTH, json=WITH_CODE)

    secrets = [_form(request)["client_secret"] for request in apple_user.apple_requests]
    assert secrets  # 가짜 서버까지는 갔다 — 아래 확인이 빈손으로 통과하지 않게
    key_body = PRIVATE_KEY.splitlines()[1]
    for leaked in (CODE, APPLE_REFRESH_TOKEN, APPLE_ACCESS_TOKEN, key_body, "000123.abc.0456", *secrets):
        assert leaked not in caplog.text


def test_the_apple_settings_default_to_empty_and_do_not_stop_boot():
    # conftest 가 필수 env 만 채운다 — 애플 키 셋이 없어도 뜬다.
    settings = Settings()
    assert (settings.apple_team_id, settings.apple_key_id, settings.apple_private_key) == ("", "", "")
