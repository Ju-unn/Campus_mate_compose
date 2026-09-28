from uuid import UUID

import httpx

from app.core.http import error_code


async def _call_grant_hearts(
    postgrest_url: str,
    service_role_key: str,
    client: httpx.AsyncClient,
    profile_id: UUID | str,
    amount: int,
    reason: str,
    ref_id: str | None,
) -> httpx.Response:
    # 주는 쪽과 쓰는 쪽이 같은 함수를 부른다 — 요청 모양을 두 곳에 적으면 한쪽만 고쳐진다.
    return await client.post(
        f"{postgrest_url}/rpc/grant_hearts",
        json={"p_profile_id": str(profile_id), "p_amount": amount, "p_reason": reason, "p_ref_id": ref_id},
        headers={
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": "application/json",
        },
    )


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
    response = await _call_grant_hearts(
        postgrest_url, service_role_key, client, profile_id, amount, reason, ref_id
    )
    response.raise_for_status()


async def spend_hearts(
    postgrest_url: str,
    service_role_key: str,
    client: httpx.AsyncClient,
    profile_id: UUID | str,
    amount: int,
    reason: str,
    ref_id: str | None = None,
) -> bool:
    """하트를 `amount` 만큼 쓴다. 잔액이 모자라면 아무것도 안 쓰고 False.

    쓰기 함수를 따로 만들지 않는다 — grant_hearts 에 음수를 넣으면 잔액 음수 금지(entitlements check)가 원장
    insert 까지 함수째 되돌리고, PostgREST 는 그 코드(23514)를 싣는다(supabase/tests/me_edit_test.sql 이 못박는다).
    """
    response = await _call_grant_hearts(
        postgrest_url, service_role_key, client, profile_id, -amount, reason, ref_id
    )
    if error_code(response) == "23514":
        return False
    response.raise_for_status()
    return True
