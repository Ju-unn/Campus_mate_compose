from uuid import UUID

import httpx


async def grant_hearts(
    postgrest_url: str,
    service_role_key: str,
    client: httpx.AsyncClient,
    profile_id: UUID | str,
    amount: int,
    reason: str,
    ref_id: str | None = None,
) -> None:
    # entitlements.heart_balance(잔액 캐시)와 heart_transactions(원장)를 한 트랜잭션에서 같이 써야 하므로
    # (ERD §6), PostgREST 두 번 호출 대신 Postgres 함수 하나(grant_hearts)로 묶는다.
    response = await client.post(
        f"{postgrest_url}/rpc/grant_hearts",
        json={"p_profile_id": str(profile_id), "p_amount": amount, "p_reason": reason, "p_ref_id": ref_id},
        headers={
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": "application/json",
        },
    )
    response.raise_for_status()
