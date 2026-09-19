import base64
import hashlib
import hmac

from app.webhook_signature import verify_webhook_signature


def _sign(secret: str, webhook_id: str, timestamp: str, body: bytes) -> str:
    key = base64.b64decode(secret.removeprefix("whsec_"))
    signed_content = f"{webhook_id}.{timestamp}.{body.decode()}".encode()
    digest = hmac.new(key, signed_content, hashlib.sha256).digest()
    return f"v1,{base64.b64encode(digest).decode()}"


def test_valid_signature_passes():
    secret = "whsec_" + base64.b64encode(b"test-secret-key-32-bytes-long!!").decode()
    body = b'{"type":"test"}'
    signature = _sign(secret, "msg_1", "1700000000", body)

    assert verify_webhook_signature(secret, "msg_1", "1700000000", body, signature) is True


def test_tampered_body_fails():
    secret = "whsec_" + base64.b64encode(b"test-secret-key-32-bytes-long!!").decode()
    signature = _sign(secret, "msg_1", "1700000000", b'{"type":"test"}')

    assert verify_webhook_signature(secret, "msg_1", "1700000000", b'{"type":"tampered"}', signature) is False


def test_one_matching_signature_among_several_passes():
    secret = "whsec_" + base64.b64encode(b"test-secret-key-32-bytes-long!!").decode()
    body = b'{"type":"test"}'
    valid = _sign(secret, "msg_1", "1700000000", body)

    assert verify_webhook_signature(secret, "msg_1", "1700000000", body, f"v0,garbage {valid}") is True
