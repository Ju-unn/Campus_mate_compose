"""애플 시험용 가짜 세계 — 진짜 애플은 부르지 않는다.

App Store 가 서명하는 JWS 와 같은 꼴(헤더 x5c = leaf · 중간 · 루트, ES256)을 시험 안에서 만든 인증서로 만든다.
진짜 애플처럼 루트는 P-384 · SHA-384, leaf 는 P-256 이다. 운영 코드는 내장한 애플 루트를 믿으므로
라우터 시험은 apple_root_ca 의존성을 이 가짜 루트로 덮는다.
"""
import base64
import json
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
from cryptography.x509.oid import NameOID

# 애플 전용 확장(애플 문서 · 공식 app-store-server-library 와 같은 값)
INTERMEDIATE_OID = x509.ObjectIdentifier("1.2.840.113635.100.6.2.1")
LEAF_OID = x509.ObjectIdentifier("1.2.840.113635.100.6.11.1")
NOW = datetime(2026, 10, 14, 12, 0, tzinfo=timezone.utc)
_YEAR = timedelta(days=365)


def _name(common_name: str) -> x509.Name:
    return x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, common_name)])


def _cert(subject: str, key, issuer: x509.Name, issuer_key, *, ca: bool, oid=None,
          not_before: datetime = NOW - _YEAR, not_after: datetime = NOW + _YEAR) -> x509.Certificate:
    builder = (x509.CertificateBuilder().subject_name(_name(subject)).issuer_name(issuer)
               .public_key(key.public_key()).serial_number(x509.random_serial_number())
               .not_valid_before(not_before).not_valid_after(not_after)
               .add_extension(x509.BasicConstraints(ca=ca, path_length=None), critical=True))
    if oid is not None:
        builder = builder.add_extension(x509.UnrecognizedExtension(oid, b"\x05\x00"), critical=False)
    hash_ = hashes.SHA384() if isinstance(issuer_key.curve, ec.SECP384R1) else hashes.SHA256()
    return builder.sign(issuer_key, hash_)


@dataclass
class Chain:
    root: x509.Certificate
    root_key: ec.EllipticCurvePrivateKey
    intermediate: x509.Certificate
    intermediate_key: ec.EllipticCurvePrivateKey
    leaf: x509.Certificate
    leaf_key: ec.EllipticCurvePrivateKey


def make_chain(*, root: Chain | None = None, intermediate_oid: bool = True, leaf_oid: bool = True,
               intermediate_ca: bool = True, leaf_not_before: datetime = NOW - _YEAR,
               leaf_not_after: datetime = NOW + _YEAR) -> Chain:
    """root 를 주면 그 체인의 루트 아래에 새 중간 · leaf 를 만든다(같은 이름이라 '이름은 맞는데 서명이 다른' 체인)."""
    if root is None:
        root_key = ec.generate_private_key(ec.SECP384R1())
        root_cert = _cert("Test Root CA - G3", root_key, _name("Test Root CA - G3"), root_key, ca=True)
    else:
        root_key, root_cert = root.root_key, root.root
    mid_key = ec.generate_private_key(ec.SECP384R1())
    mid = _cert("Test WWDR G6", mid_key, root_cert.subject, root_key, ca=intermediate_ca,
                oid=INTERMEDIATE_OID if intermediate_oid else None)
    leaf_key = ec.generate_private_key(ec.SECP256R1())
    leaf = _cert("Test StoreKit Signing", leaf_key, mid.subject, mid_key, ca=False,
                 oid=LEAF_OID if leaf_oid else None, not_before=leaf_not_before, not_after=leaf_not_after)
    return Chain(root_cert, root_key, mid, mid_key, leaf, leaf_key)


CHAIN = make_chain()


def b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def der_b64(cert: x509.Certificate) -> str:
    """x5c 칸은 base64url 이 아니라 표준 base64 DER 이다(RFC 7515 §4.1.6)."""
    return base64.b64encode(cert.public_bytes(serialization.Encoding.DER)).decode()


def x5c(chain: Chain) -> list[str]:
    return [der_b64(chain.leaf), der_b64(chain.intermediate), der_b64(chain.root)]


def sign(payload, chain: Chain = CHAIN, *, alg: str = "ES256", certs: list[str] | None = None, key=None) -> str:
    """애플이 하듯 leaf 키로 ES256(r||s 64바이트) 서명한 JWS. key 를 주면 그 키로 서명한다(leaf 와 다른 키)."""
    header = {"alg": alg, "x5c": x5c(chain) if certs is None else certs}
    signing_input = f"{b64url(json.dumps(header).encode())}.{b64url(json.dumps(payload).encode())}"
    r, s = decode_dss_signature((key or chain.leaf_key).sign(signing_input.encode(), ec.ECDSA(hashes.SHA256())))
    return f"{signing_input}.{b64url(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))}"


def unsigned(payload, chain: Chain = CHAIN) -> str:
    """alg none — 서명 칸이 빈 JWS."""
    header = {"alg": "none", "x5c": x5c(chain)}
    return f"{b64url(json.dumps(header).encode())}.{b64url(json.dumps(payload).encode())}."


def tamper_signature(jws: str) -> str:
    """서명 바이트 하나를 바꾼다(길이 · 꼴은 그대로)."""
    head, body, signature = jws.split(".")
    raw = bytearray(base64.urlsafe_b64decode(signature + "=" * (-len(signature) % 4)))
    raw[10] ^= 0x01
    return f"{head}.{body}.{b64url(bytes(raw))}"


def swap_payload(jws: str, payload) -> str:
    """헤더 · 서명은 그대로 두고 본문만 바꾼다(서명 뒤 본문 고치기)."""
    head, _, signature = jws.split(".")
    return f"{head}.{b64url(json.dumps(payload).encode())}.{signature}"
