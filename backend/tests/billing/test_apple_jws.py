"""애플 서명(JWS) 검증 — app/billing/apple.py verify_jws. 애플 알림은 공개 주소로 오므로 믿는 근거는 이 검증뿐이다.

체인(leaf → 중간 → 루트)의 서명 · 유효기간 · CA 표시 · 애플 전용 확장 OID 를 보고, leaf 공개키로 JWS ES256 서명을 본다.
인증서는 시험 안에서 만든다(apple_world). 운영 루트(애플 Root CA G3)는 지문으로만 확인한다.
"""
import hashlib
from datetime import timedelta

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID

from apple_world import (CHAIN, NOW, b64url, der_b64, make_chain, sign, swap_payload, tamper_signature, unsigned,
                         x5c)
from app.billing.apple import APPLE_ROOT_CA_G3, AppleJwsInvalid, verify_jws

PAYLOAD = {"transactionId": "2000000812345678", "bundleId": "io.github.juunn.campusmate"}


def _rejects(token: str, root=CHAIN.root, now=NOW):
    with pytest.raises(AppleJwsInvalid):
        verify_jws(token, now, root)


def test_a_jws_signed_by_the_leaf_of_a_trusted_chain_gives_its_payload():
    assert verify_jws(sign(PAYLOAD), NOW, CHAIN.root) == PAYLOAD


# 서명 ----------------------------------------------------------------------------------------------

def test_a_changed_signature_byte_is_rejected():
    _rejects(tamper_signature(sign(PAYLOAD)))


def test_a_payload_changed_after_signing_is_rejected():
    _rejects(swap_payload(sign(PAYLOAD), {**PAYLOAD, "productId": "heart_800"}))


def test_a_signature_by_a_key_other_than_the_leaf_is_rejected():
    _rejects(sign(PAYLOAD, key=ec.generate_private_key(ec.SECP256R1())))


@pytest.mark.parametrize("make", [
    lambda: unsigned(PAYLOAD),
    lambda: sign(PAYLOAD, alg="none"),
    lambda: sign(PAYLOAD, alg="HS256"),
    lambda: sign(PAYLOAD, alg="ES384"),
    lambda: sign(PAYLOAD, alg="es256"),
])
def test_only_es256_is_accepted(make):
    _rejects(make())


# 체인 ----------------------------------------------------------------------------------------------

def test_a_chain_under_another_root_is_rejected():
    _rejects(sign(PAYLOAD, make_chain()))


def test_a_chain_whose_third_certificate_is_our_root_but_whose_intermediate_is_not_is_rejected():
    # x5c 의 세 번째 칸은 믿지 않는다 — 중간이 우리 루트로 서명됐는지를 본다.
    other = make_chain()
    _rejects(sign(PAYLOAD, other, certs=[der_b64(other.leaf), der_b64(other.intermediate), der_b64(CHAIN.root)]))


def test_a_leaf_not_issued_by_the_intermediate_is_rejected():
    # 같은 루트 아래 두 체인 — 이름은 같지만 leaf 를 서명한 중간이 다르다.
    sibling = make_chain(root=CHAIN)
    _rejects(sign(PAYLOAD, sibling, certs=[der_b64(sibling.leaf), der_b64(CHAIN.intermediate), der_b64(CHAIN.root)]))


def test_an_intermediate_without_the_apple_oid_is_rejected():
    _rejects(sign(PAYLOAD, make_chain(root=CHAIN, intermediate_oid=False)))


def test_a_leaf_without_the_apple_oid_is_rejected():
    _rejects(sign(PAYLOAD, make_chain(root=CHAIN, leaf_oid=False)))


def test_an_intermediate_that_is_not_a_ca_is_rejected():
    _rejects(sign(PAYLOAD, make_chain(root=CHAIN, intermediate_ca=False)))


def test_an_expired_leaf_is_rejected():
    _rejects(sign(PAYLOAD, make_chain(root=CHAIN, leaf_not_after=NOW - timedelta(seconds=1))))


def test_a_leaf_that_is_not_valid_yet_is_rejected():
    _rejects(sign(PAYLOAD, make_chain(root=CHAIN, leaf_not_before=NOW + timedelta(seconds=1))))


def test_the_clock_is_the_given_now():
    token = sign(PAYLOAD)

    assert verify_jws(token, NOW, CHAIN.root) == PAYLOAD
    _rejects(token, now=NOW + timedelta(days=2 * 365))


@pytest.mark.parametrize("certs", [
    [],
    x5c(CHAIN)[:2],
    [*x5c(CHAIN), x5c(CHAIN)[2]],
    ["not base64 !!", *x5c(CHAIN)[1:]],
    ["AAAA", *x5c(CHAIN)[1:]],
    [1, 2, 3],
])
def test_an_x5c_that_is_not_three_certificates_is_rejected(certs):
    _rejects(sign(PAYLOAD, certs=certs))


# 꼴 ------------------------------------------------------------------------------------------------

@pytest.mark.parametrize("token", ["", "a.b", "a.b.c.d", "...", "x.y.z", "eyJhbGciOiJFUzI1NiJ9.e30.AAAA"])
def test_a_token_that_is_not_a_jws_is_rejected(token):
    _rejects(token)


def test_a_deeply_nested_header_is_rejected_not_crashed():
    # 헤더는 서명 확인 전에 읽는다 — 알림 주소는 누구나 부를 수 있어 500 이 아니라 거절이어야 한다.
    _rejects(f"{b64url(b'[' * 50_000)}.e30.AAAA")


def test_a_payload_that_is_not_an_object_is_rejected():
    _rejects(sign(["not", "an", "object"]))


def test_the_rejection_reason_carries_no_token_content():
    token = tamper_signature(sign(PAYLOAD))

    with pytest.raises(AppleJwsInvalid) as caught:
        verify_jws(token, NOW, CHAIN.root)

    reason = str(caught.value)
    assert reason and PAYLOAD["transactionId"] not in reason and token.split(".")[0][:20] not in reason


# 운영 루트 ------------------------------------------------------------------------------------------

def test_the_embedded_root_is_apple_root_ca_g3():
    """https://www.apple.com/certificateauthority/AppleRootCA-G3.cer — 지문은 애플 지원 문서
    'List of available root certificates in iOS18 …'(support.apple.com/en-us/121672)의 값과 같다(2026-10-14 대조)."""
    der = APPLE_ROOT_CA_G3.public_bytes(serialization.Encoding.DER)

    assert hashlib.sha256(der).hexdigest() == "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179"
    assert APPLE_ROOT_CA_G3.subject.get_attributes_for_oid(NameOID.COMMON_NAME)[0].value == "Apple Root CA - G3"
    assert APPLE_ROOT_CA_G3.not_valid_after_utc.year == 2039


def test_without_a_root_argument_the_apple_root_is_used():
    with pytest.raises(AppleJwsInvalid):
        verify_jws(sign(PAYLOAD), NOW)
