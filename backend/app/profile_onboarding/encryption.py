from uuid import UUID

import httpx


async def set_encrypted_phone_number(
    postgrest_url: str,
    service_role_key: str,
    client: httpx.AsyncClient,
    profile_id: UUID,
    phone_number: str,
    encryption_key: str,
) -> None:
    # 암호화 자체는 DB 안(pgcrypto pgp_sym_encrypt)에서 한다 — 여기서는 RPC 를 부르는 얇은 wrapper 다.
    # 키는 JSON 바디로만 넘긴다. URL 쿼리스트링에 넣으면 웹서버 접근 로그에 그대로 남는다(2026-09-20 사용자 승인 조건).
    response = await client.post(
        f"{postgrest_url}/rpc/set_phone_number",
        json={"p_profile_id": str(profile_id), "p_phone": phone_number, "p_key": encryption_key},
        headers={
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": "application/json",
        },
    )
    response.raise_for_status()
