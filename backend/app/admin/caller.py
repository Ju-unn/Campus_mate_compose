"""관리자 웹 대시보드의 관문(설계 10-18 §6-3). 순서: 로그인(401) → 2단계 인증 aal2(403 mfa_required) → admin_users(403 not_admin).

학교 메일 관문(get_verified_caller)은 쓰지 않는다 — 관리자 계정(운영자 전용 구글 계정)은 학교 메일이 없다.
2단계를 명단보다 먼저 본다 — 2단계 전에는 그 계정이 관리자인지도 알려 주지 않는다.
"""
import base64
import json
from typing import NamedTuple
from uuid import UUID

import httpx
from fastapi import Depends, Header, HTTPException

from app.admin.repository import AdminRepository
from app.core.deps import get_client, get_settings
from app.settings import Settings
from app.student_verification.current_user import get_current_user_id

# 403 의 detail 에 싣는 기계용 이유 코드. 관리자 웹은 이 값으로 2단계 입력 화면 / 권한 없음 화면을 가른다.
MFA_REQUIRED = "mfa_required"
NOT_ADMIN = "not_admin"


class AdminCaller(NamedTuple):
    """Caller(core/deps.py)와 같은 모양 — 설정 · HTTP 클라이언트 · 관문을 통과한 관리자 auth 사용자 id."""

    settings: Settings
    client: httpx.AsyncClient
    admin_user_id: UUID


def token_aal(authorization: str) -> str | None:
    """`Bearer <JWT>` 의 페이로드 aal 클레임. 서명은 보지 않는다 — 바로 앞에서 같은 토큰을 Supabase(/auth/v1/user)가
    확인했다. 읽을 수 없는 토큰은 None(= 2단계 아님)이다 — 막는 쪽으로 넘어진다."""
    try:
        payload = authorization.rsplit(" ", 1)[-1].split(".")[1]
        claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
    except (IndexError, ValueError):  # binascii.Error · JSONDecodeError · UnicodeDecodeError 는 모두 ValueError 다.
        return None
    return claims.get("aal") if isinstance(claims, dict) else None


async def get_admin_caller(
    authorization: str | None = Header(default=None),
    settings: Settings = Depends(get_settings),
    client: httpx.AsyncClient = Depends(get_client),
) -> AdminCaller:
    user_id = await get_current_user_id(settings, client, authorization)
    if token_aal(authorization) != "aal2":
        raise HTTPException(status_code=403, detail=MFA_REQUIRED)
    # 명단은 Supabase 가 확인한 id 로 찾는다(페이로드의 sub 를 믿지 않는다).
    repo = AdminRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    if not await repo.is_admin(user_id):
        raise HTTPException(status_code=403, detail=NOT_ADMIN)
    return AdminCaller(settings, client, user_id)
