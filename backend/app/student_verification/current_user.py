from uuid import UUID

import httpx
from fastapi import Header, HTTPException

from app.settings import Settings


async def get_current_user_id(
    settings: Settings,
    client: httpx.AsyncClient,
    authorization: str | None = Header(default=None),
) -> UUID:
    if authorization is None:
        raise HTTPException(status_code=401, detail="로그인이 필요해요")
    response = await client.get(
        f"{settings.auth_url}/user",
        headers={"Authorization": authorization, "apikey": settings.supabase_service_role_key},
    )
    if response.status_code != 200:
        raise HTTPException(status_code=401, detail="세션이 만료됐어요, 다시 로그인해 주세요")
    return UUID(response.json()["id"])
