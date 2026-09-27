from uuid import UUID

import httpx

from app.signup_policy import IDENTITY_KEY_VERSION, bytea_literal, hash_phone


async def set_encrypted_phone_number(
    postgrest_url: str,
    service_role_key: str,
    client: httpx.AsyncClient,
    profile_id: UUID,
    phone_number: str,
    encryption_key: str,
    *,
    identity_key: str,
) -> None:
    # 암호화 자체는 DB 안(pgcrypto pgp_sym_encrypt)에서 한다 — 여기서는 RPC 를 부르는 얇은 wrapper 다.
    # 키는 JSON 바디로만 넘긴다. URL 쿼리스트링에 넣으면 웹서버 접근 로그에 그대로 남는다(2026-09-20 사용자 승인 조건).
    # 지인 차단용 HMAC 도 같이 넘긴다(조각 6 B4). 해시 키는 DB 에 들이지 않고 여기서 떠서 값만 보낸다.
    # 입력은 저장하는 E.164 값 그대로다 — 연락처 등록(safety)이 같은 모양을 해시해야 대조가 맞는다.
    response = await client.post(
        f"{postgrest_url}/rpc/set_phone_number",
        json={
            "p_profile_id": str(profile_id), "p_phone": phone_number, "p_key": encryption_key,
            "p_phone_hmac": bytea_literal(hash_phone(identity_key, phone_number)),
            "p_phone_hmac_key_version": IDENTITY_KEY_VERSION,
        },
        headers={
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": "application/json",
        },
    )
    response.raise_for_status()
