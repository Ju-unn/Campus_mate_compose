"""기계가 부르는 엔드포인트(Cloud Tasks · Cloud Scheduler)의 신원 확인.

Cloud Run 이 `--allow-unauthenticated` 라 이 엔드포인트들은 스스로를 지킨다
(`cards/batch_router.py` 가 공유 비밀로 하는 일을, 여기서는 구글이 서명한 ID 토큰으로 한다).

**설정을 직접 읽지 않는다** — 값은 부르는 라우터가 넘긴다. 아바타 워커와 조각 6 스케줄러가 서로 다른
환경변수를 보고, 그래야 테스트가 설정 없이 돈다.
"""
import asyncio

from fastapi import HTTPException
from google.auth.exceptions import GoogleAuthError
from google.auth.transport.requests import Request as GoogleAuthRequest
from google.oauth2 import id_token

from app.core import errors


async def verify_oidc_token(
    authorization: str | None, *, audience: str, service_account_email: str
) -> None:
    """`Authorization: Bearer <구글 ID 토큰>` 을 확인한다. 통과하면 조용히 돌아오고, 아니면 401 이다."""
    # 설정을 빠뜨린 배포가 열린 문이 되지 않게 아무도 통과시키지 않는다(card_batch_secret 과 같은 규칙).
    if not service_account_email or not audience or not authorization:
        raise HTTPException(status_code=401, detail=errors.UNAUTHORIZED)

    token = authorization.removeprefix("Bearer ").strip()
    try:
        # 인증서 조회가 동기 I/O 라 스레드로 돌린다(FcmSender 의 credentials.refresh 와 같은 이유).
        claims = await asyncio.to_thread(
            id_token.verify_oauth2_token, token, GoogleAuthRequest(), audience
        )
    except (ValueError, GoogleAuthError):
        # 서명·audience 불일치는 ValueError, 인증서 조회 실패 같은 전송 오류는 GoogleAuthError 다.
        raise HTTPException(status_code=401, detail=errors.UNAUTHORIZED) from None

    # audience 만 보면 그 URL 을 아는 **다른** 서비스 계정도 통과한다 — 누가 발급했는지까지 본다.
    if not claims.get("email_verified") or claims.get("email") != service_account_email:
        raise HTTPException(status_code=401, detail=errors.UNAUTHORIZED)
