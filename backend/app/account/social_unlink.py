"""탈퇴 때 소셜 연결 끊기. 카카오는 연결 끊기, 애플은 토큰 철회(App Store 5.1.1(v)). 구글은 하지 않는다.

카카오 회원번호는 `GET {auth_url}/user` 의 identities 중 provider kakao 의 identity_data.sub 다.
애플은 우리가 signInWithIdToken 으로 로그인해 refresh_token 이 없다 — 앱이 탈퇴 직전 애플 창을 한 번 더 띄워 받은
일회용 authorizationCode 를 서버가 refresh_token 으로 바꾸고 바로 철회한다(토큰은 저장하지 않는다).
회원번호 · 코드 · 토큰 · 키는 어디에도 남기지 않는다 — 실패는 부르는 쪽(account/router.py)이 단계 이름만 경고로 남긴다.
"""
import time

import httpx

from app.settings import Settings
from app.student_verification.current_user import fetch_auth_user

KAKAO_UNLINK_URL = "https://kapi.kakao.com/v1/user/unlink"
# 네이티브 앱 흐름(iOS 시스템 창)이라 client_id 는 Services ID 가 아니라 번들 ID 다.
APPLE_CLIENT_ID = "io.github.juunn.campusmate"
APPLE_AUDIENCE = "https://appleid.apple.com"
APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token"
APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke"
# 두 요청을 보낼 동안만 쓰면 된다(애플 상한은 6개월).
APPLE_CLIENT_SECRET_SECONDS = 300
# 앱 전체가 나눠 쓰는 클라이언트 설정과 상관없이 애플 요청은 각각 5초에서 끊는다(탈퇴 응답이 늘어지지 않게).
APPLE_TIMEOUT_SECONDS = 5.0


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


def apple_client_secret(settings: Settings, now: float) -> str:
    """애플 토큰 API 의 client_secret — 팀의 Sign in with Apple 키로 서명한 ES256 JWT(헤더 kid = 키 ID).

    여기서 가져온다 — cryptography 가 빠진 google-auth 에는 ES256Signer 가 없는데, 맨 위에서 가져오면 서버 전체가
    뜨지 않는다. 여기서 실패하면 애플 단계만 경고로 끝난다."""
    from google.auth import jwt
    from google.auth.crypt import ES256Signer

    signer = ES256Signer.from_string(settings.apple_private_key, settings.apple_key_id)
    issued = int(now)
    claims = {"iss": settings.apple_team_id, "iat": issued, "exp": issued + APPLE_CLIENT_SECRET_SECONDS,
              "aud": APPLE_AUDIENCE, "sub": APPLE_CLIENT_ID}
    return jwt.encode(signer, claims).decode()


async def exchange_apple_code(settings: Settings, client: httpx.AsyncClient,
                              authorization_code: str | None) -> str | None:
    """일회용 코드를 refresh_token 으로 바꿔 돌려준다. 키 셋 중 하나라도 비었거나 코드가 없으면
    (카카오 · 구글 사용자, 애플 창을 닫은 사람) 아무것도 하지 않고 None 이다. 실패하면 예외다."""
    keys = (settings.apple_team_id, settings.apple_key_id, settings.apple_private_key)
    if not (all(keys) and authorization_code):
        return None
    response = await client.post(APPLE_TOKEN_URL, timeout=APPLE_TIMEOUT_SECONDS, data={
        "client_id": APPLE_CLIENT_ID, "client_secret": apple_client_secret(settings, time.time()),
        "code": authorization_code, "grant_type": "authorization_code",
    })
    response.raise_for_status()
    return response.json()["refresh_token"]


async def revoke_apple_token(settings: Settings, client: httpx.AsyncClient, refresh_token: str | None) -> None:
    """[exchange_apple_code] 가 준 refresh_token 을 철회한다. 없으면(교환을 건너뛰었거나 실패) 아무것도 하지 않는다."""
    if not refresh_token:
        return
    response = await client.post(APPLE_REVOKE_URL, timeout=APPLE_TIMEOUT_SECONDS, data={
        "client_id": APPLE_CLIENT_ID, "client_secret": apple_client_secret(settings, time.time()),
        "token": refresh_token, "token_type_hint": "refresh_token",
    })
    response.raise_for_status()
