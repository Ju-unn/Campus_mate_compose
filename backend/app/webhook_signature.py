import base64
import hashlib
import hmac
import time

# Standard Webhooks 권장 허용 오차 — 재전송 공격 방지용.
_TIMESTAMP_TOLERANCE_SECONDS = 300


def verify_webhook_signature(
    secret: str,
    webhook_id: str,
    timestamp: str,
    body: bytes,
    signature_header: str,
) -> bool:
    """Standard Webhooks 서명을 검증한다. 공백으로 구분된 서명 중 하나라도
    맞으면 통과시킨다(발신 측 키 회전 대비, Standard Webhooks 규격).
    현재 시각과 ±5분을 벗어난 timestamp 는 재전송 공격으로 보고 거부한다."""
    if not _is_timestamp_fresh(timestamp):
        return False

    # Supabase 대시보드는 시크릿을 "v1,whsec_<base64>" 로 보여준다 — 그대로 붙여넣혀도 되게 둘 다 벗긴다.
    key = base64.b64decode(secret.removeprefix("v1,").removeprefix("whsec_"))
    signed_content = f"{webhook_id}.{timestamp}.{body.decode()}".encode()
    expected = hmac.new(key, signed_content, hashlib.sha256).digest()
    expected_encoded = base64.b64encode(expected).decode()

    for candidate in signature_header.split(" "):
        _, _, value = candidate.partition(",")
        if hmac.compare_digest(value, expected_encoded):
            return True
    return False


def _is_timestamp_fresh(timestamp: str) -> bool:
    try:
        signed_at = int(timestamp)
    except ValueError:
        return False
    return abs(time.time() - signed_at) <= _TIMESTAMP_TOLERANCE_SECONDS
