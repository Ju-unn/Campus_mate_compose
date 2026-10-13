"""애플 인앱결제(아이폰 하트 구매) — App Store Server API 조회와 애플 서명(JWS) 검증.
계획서 바탕화면 출시준비/애플_인앱결제_구현계획_초안.md 3절 · 2026-10-14 사용자 결정.

새 JWT 패키지 없이 cryptography(2026-10-14 사용자 승인)와 표준 라이브러리만 쓴다.
애플이 서명한 값(거래 정보 · 알림)은 헤더 x5c 의 인증서 체인을 **코드에 내장한 애플 루트**까지 확인한 뒤에만 믿는다.
**거래 번호는 요청 주소에 들어간다.** 이 모듈과 부르는 쪽은 주소 · 예외 문구 · JWS · 우리 JWT · 키를 로그에 남기지 않는다.
"""
import base64
import binascii
import json
import uuid
from datetime import datetime

import httpx
from cryptography import x509
from cryptography.exceptions import InvalidSignature, UnsupportedAlgorithm
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature, encode_dss_signature

# frontend/ios Runner 의 번들 ID(project.pbxproj). 바뀌지 않는 값이라 설정으로 만들지 않는다(play.PACKAGE_NAME 과 같다).
BUNDLE_ID = "io.github.juunn.campusmate"
PRODUCTION_URL = "https://api.storekit.itunes.apple.com"
SANDBOX_URL = "https://api.storekit-sandbox.itunes.apple.com"
_AUDIENCE = "appstoreconnect-v1"
# 애플 상한은 60분 — 요청마다 새로 만들어 짧게 둔다.
_TOKEN_SECONDS = 300
_TIMEOUT_SECONDS = 10.0
# 고정값이다. 바꾸면 이미 산 거래의 appAccountToken 이 전부 '다른 계정'이 된다(시험이 결과를 글자 그대로 못박는다).
_ACCOUNT_NAMESPACE = uuid.UUID("61ee9e9f-3540-4e02-b910-ed8e45e2a496")

# 애플 전용 확장 — 중간(Apple WWDR) · leaf(App Store 서명). 애플 공식 app-store-server-library 가 보는 값과 같다.
_INTERMEDIATE_OID = x509.ObjectIdentifier("1.2.840.113635.100.6.2.1")
_LEAF_OID = x509.ObjectIdentifier("1.2.840.113635.100.6.11.1")

# Apple Root CA - G3. https://www.apple.com/certificateauthority/AppleRootCA-G3.cer 그대로(2039-04-30 만료).
# SHA-256 지문 63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79 —
# 애플 지원 문서 support.apple.com/en-us/121672(신뢰 루트 목록)의 값과 대조했다(2026-10-14). 시험이 이 지문을 다시 본다.
APPLE_ROOT_CA_G3 = x509.load_pem_x509_certificate(b"""-----BEGIN CERTIFICATE-----
MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwS
QXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9u
IEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcN
MTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBS
b290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9y
aXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49
AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtf
TjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517
IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySr
MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gA
MGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4
at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM
6BgD56KyKA==
-----END CERTIFICATE-----
""")


def apple_account_token(profile_id) -> str:
    """구매 창에 싣는 계정 표시(appAccountToken — 애플은 UUID 만 받는다). profile_id 에서 결정적으로 만든 UUIDv5 라
    profile_id 를 그대로 애플에 보내지 않는다(구글 play.account_token 과 같은 역할)."""
    return str(uuid.uuid5(_ACCOUNT_NAMESPACE, str(profile_id)))


def is_account_token(value, profile_id) -> bool:
    """애플이 돌려준 appAccountToken 이 이 사람의 것인가. 대소문자 · 꼴 차이는 UUID 로 읽어 없앤다(Swift 는 대문자로 쓴다)."""
    try:
        return uuid.UUID(str(value)) == uuid.UUID(apple_account_token(profile_id))
    except ValueError:
        return False


class AppleJwsInvalid(Exception):
    """애플이 서명했다고 볼 수 없다. 문구는 이유 이름뿐이다 — 토큰 · 거래 내용을 싣지 않는다(로그로 간다)."""


class AppleUnavailable(Exception):
    """애플이 지금 답하지 못한다(5xx · 429 · 시간 초과 · 401/403 = 우리 키 설정 · 키를 못 읽음). 부르는 쪽은 503 — 앱이 다시 보낸다."""


def _b64url(part: str) -> bytes:
    return base64.urlsafe_b64decode(part + "=" * (-len(part) % 4))


def _b64url_encode(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def _check_chain(leaf: x509.Certificate, intermediate: x509.Certificate, root: x509.Certificate, now: datetime) -> None:
    for cert in (leaf, intermediate, root):
        if not cert.not_valid_before_utc <= now <= cert.not_valid_after_utc:
            raise AppleJwsInvalid("certificate_expired")
    try:
        # 이름이 맞는지와 서명을 같이 본다. x5c 의 세 번째(루트) 칸은 쓰지 않는다 — 믿는 루트는 내장한 것뿐이다.
        intermediate.verify_directly_issued_by(root)
        leaf.verify_directly_issued_by(intermediate)
    except (ValueError, TypeError, InvalidSignature):
        raise AppleJwsInvalid("chain") from None
    try:
        is_ca = intermediate.extensions.get_extension_for_class(x509.BasicConstraints).value.ca
        intermediate.extensions.get_extension_for_oid(_INTERMEDIATE_OID)
        leaf.extensions.get_extension_for_oid(_LEAF_OID)
    except x509.ExtensionNotFound:
        raise AppleJwsInvalid("apple_oid") from None
    if not is_ca:
        raise AppleJwsInvalid("intermediate_not_ca")


def verify_jws(token: str, now: datetime, root: x509.Certificate = APPLE_ROOT_CA_G3) -> dict:
    """애플이 서명한 JWS(거래 정보 · 알림) → 본문. 믿을 수 없으면 AppleJwsInvalid.

    now 는 인증서 유효기간을 보는 기준 시각, root 는 시험이 가짜 루트를 끼우는 자리다(운영은 내장 애플 루트)."""
    try:
        head, body, signature = token.split(".")
        header = json.loads(_b64url(head))
        # alg 는 ES256 하나만 — none · HS256 같은 '알고리즘 바꿔치기'를 막는다.
        if not isinstance(header, dict) or header.get("alg") != "ES256":
            raise AppleJwsInvalid("alg")
        certs = header.get("x5c")
        if not isinstance(certs, list) or len(certs) != 3 or not all(isinstance(c, str) for c in certs):
            raise AppleJwsInvalid("x5c")
        leaf, intermediate = (x509.load_der_x509_certificate(base64.b64decode(c, validate=True)) for c in certs[:2])
        _check_chain(leaf, intermediate, root, now)
        public_key = leaf.public_key()
        raw = _b64url(signature)
        if not isinstance(public_key, ec.EllipticCurvePublicKey) or len(raw) != 64:
            raise AppleJwsInvalid("signature")
        # JWS 의 ES256 서명은 r||s 32바이트씩 — cryptography 는 DER 을 받는다.
        der = encode_dss_signature(int.from_bytes(raw[:32], "big"), int.from_bytes(raw[32:], "big"))
        public_key.verify(der, f"{head}.{body}".encode("ascii"), ec.ECDSA(hashes.SHA256()))
        payload = json.loads(_b64url(body))
    except AppleJwsInvalid:
        raise
    except InvalidSignature:
        raise AppleJwsInvalid("signature") from None
    except (ValueError, TypeError, binascii.Error, UnicodeError, RecursionError):
        # json · base64 · 인증서 읽기 실패, '점이 셋이 아님'(split 언패킹), 아주 깊게 겹친 JSON 이 여기로 온다.
        raise AppleJwsInvalid("malformed") from None
    if not isinstance(payload, dict):
        raise AppleJwsInvalid("payload")
    return payload


class AppleApi:
    """App Store Server API. 키(앱 내 구입 키 .p8)는 Settings 에서 받는다 — 비었으면 부르는 쪽이 이 객체를 만들지 않는다."""

    def __init__(self, client: httpx.AsyncClient, key_id: str, issuer_id: str, private_key: str):
        self._client = client
        self._key_id = key_id
        self._issuer_id = issuer_id
        self._private_key = private_key

    def _bearer(self, now: datetime) -> str:
        """애플이 정한 ES256 JWT(헤더 kid = 키 ID, iss = 발급자 ID, aud, bid = 번들 ID). 키를 못 읽으면 AppleUnavailable."""
        try:
            key = serialization.load_pem_private_key(self._private_key.encode(), password=None)
        except (ValueError, TypeError, UnsupportedAlgorithm):
            raise AppleUnavailable("key") from None
        if not isinstance(key, ec.EllipticCurvePrivateKey):
            raise AppleUnavailable("key")
        issued = int(now.timestamp())
        header = {"alg": "ES256", "kid": self._key_id, "typ": "JWT"}
        claims = {"iss": self._issuer_id, "iat": issued, "exp": issued + _TOKEN_SECONDS, "aud": _AUDIENCE,
                  "bid": BUNDLE_ID}
        signing_input = ".".join(_b64url_encode(json.dumps(part).encode()) for part in (header, claims))
        r, s = decode_dss_signature(key.sign(signing_input.encode(), ec.ECDSA(hashes.SHA256())))
        return f"{signing_input}.{_b64url_encode(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))}"

    async def signed_transaction(self, transaction_id: str, now: datetime) -> str | None:
        """그 거래의 signedTransactionInfo(애플이 서명한 JWS — 검증은 부르는 쪽이 verify_jws 로).

        운영 주소에 없으면(404) 샌드박스 주소에 한 번 더 묻는다(애플 권장 순서 — TestFlight · 심사 거래는 샌드박스).
        둘 다 모르거나 애플이 거래 번호 꼴을 거절하면(400) None."""
        headers = {"Authorization": f"Bearer {self._bearer(now)}"}
        for base_url in (PRODUCTION_URL, SANDBOX_URL):
            try:
                response = await self._client.get(f"{base_url}/inApps/v1/transactions/{transaction_id}",
                                                  headers=headers, timeout=_TIMEOUT_SECONDS)
            except httpx.TransportError:
                # from None — 원래 예외 문구에는 거래 번호가 든 주소가 있다. 트레이스백에 딸려 가지 않게 끊는다.
                raise AppleUnavailable("transport") from None
            if response.status_code == 404:
                continue
            if response.status_code == 400:
                return None
            if not response.is_success:
                raise AppleUnavailable(response.status_code)
            try:
                signed = response.json().get("signedTransactionInfo")
            except (ValueError, AttributeError):
                signed = None
            if not isinstance(signed, str):
                raise AppleUnavailable("body")
            return signed
        return None
