"""탈퇴 때 소셜 연결 끊기. 지금은 카카오만 한다(애플 토큰 철회는 애플 로그인 PR 몫).

카카오 회원번호는 `GET {auth_url}/user` 의 identities 중 provider kakao 의 identity_data.sub 다.
회원번호와 키는 어디에도 남기지 않는다 — 실패는 부르는 쪽(account/router.py)이 단계 이름만 경고로 남긴다.
"""
import httpx

from app.settings import Settings
from app.student_verification.current_user import fetch_auth_user

KAKAO_UNLINK_URL = "https://kapi.kakao.com/v1/user/unlink"


def kakao_member_id(auth_user: dict) -> str | None:
    for identity in auth_user.get("identities") or []:
        if identity.get("provider") == "kakao":
            sub = (identity.get("identity_data") or {}).get("sub")
            return str(sub) if sub else None
    return None


async def unlink_kakao(settings: Settings, client: httpx.AsyncClient, authorization: str) -> None:
    """키(kakao_admin_key)가 비었거나 카카오 계정이 아니면 아무것도 하지 않는다. 실패하면 예외다."""
    if not settings.kakao_admin_key:
        return
    member_id = kakao_member_id(await fetch_auth_user(settings, client, authorization))
    if member_id is None:
        return
    response = await client.post(
        KAKAO_UNLINK_URL,
        headers={"Authorization": f"KakaoAK {settings.kakao_admin_key}"},
        data={"target_id_type": "user_id", "target_id": member_id},
    )
    response.raise_for_status()
