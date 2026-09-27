"""한 번 쓰는 백필(B4): 조각 6 전에 저장된 번호에 지인 차단 HMAC 을 채운다."""
import json

import httpx

from app.signup_policy import IDENTITY_KEY_VERSION, bytea_literal, hash_phone
from scripts.backfill_phone_hmac import PhoneHmacBackfill

PHONES = {  # profile_id → 복호화 결과
    "p1": "010-1234-5678",   # 옛 저장 모양 — to_e164 로 맞춘 뒤 해시한다
    "p2": "02-123-4567",     # 휴대전화가 아님 → 건너뛰고 센다
    "p3": None,              # 복호화 결과 없음 → 건너뛴다
    "p4": "+821099998888",
}


async def test_backfill_fills_only_null_rows_pages_by_key_and_is_safe_to_rerun():
    hmacs: dict[str, str | None] = {pid: None for pid in PHONES}
    sent: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        sent.append(request)
        params = request.url.params
        if request.url.path == "/rest/v1/rpc/decrypt_phone_number":
            # PostgREST 는 스칼라 null 도 본문 `null` 로 준다(httpx 의 json=None 은 빈 본문이라 직접 싣는다).
            phone = PHONES[json.loads(request.content)["p_profile_id"]]
            return httpx.Response(200, content=json.dumps(phone), headers={"Content-Type": "application/json"})
        if request.method == "PATCH":
            pid = params["profile_id"].removeprefix("eq.")
            assert params["phone_hmac"] == "is.null"   # 새 서버가 그 사이 채운 값은 덮지 않는다
            hmacs[pid] = json.loads(request.content)["phone_hmac"]
            return httpx.Response(204)
        assert params["phone_number"] == "not.is.null" and params["phone_hmac"] == "is.null"
        after = params.get("profile_id", "gt.").removeprefix("gt.")
        rows = [pid for pid in sorted(hmacs) if hmacs[pid] is None and pid > after]
        return httpx.Response(200, json=[{"profile_id": pid} for pid in rows[:int(params["limit"])]])

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        job = PhoneHmacBackfill("https://x.supabase.co/rest/v1", "service-key", client)
        first = await job.run(phone_key="phone-key", identity_key="identity-key", page=2)
        again = await job.run(phone_key="phone-key", identity_key="identity-key", page=2)

    assert first == {"filled": 2, "skipped": 2}
    # 다시 돌리면 채운 행은 고르지 않는다. 휴대전화가 아닌 행은 매번 건너뛴 수로만 남는다.
    assert again == {"filled": 0, "skipped": 2}
    assert hmacs["p1"] == bytea_literal(hash_phone("identity-key", "+821012345678"))
    assert hmacs["p4"] == bytea_literal(hash_phone("identity-key", "+821099998888"))
    patch = next(r for r in sent if r.method == "PATCH")
    assert json.loads(patch.content)["phone_hmac_key_version"] == IDENTITY_KEY_VERSION
    # 키는 JSON 바디로만 — URL(접근 로그)에는 없다.
    assert all("phone-key" not in str(r.url) and "identity-key" not in str(r.url) for r in sent)
