import logging
from contextlib import asynccontextmanager

import cryptography
import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.account.batch_router import router as account_batch_router
from app.account.router import router as account_router
from app.admin.cors import install_admin_cors
from app.admin.router import router as admin_router
from app.auth_hooks.router import router as auth_hooks_router
from app.billing.apple_router import router as billing_apple_router
from app.billing.batch_router import router as billing_batch_router
from app.billing.router import router as billing_router
from app.cards.batch_router import router as cards_batch_router
from app.cards.router import router as cards_router
from app.chat.batch_router import router as chat_batch_router
from app.chat.router import router as chat_router
from app.community.router import router as community_router
from app.consents.router import router as consents_router
from app.core.deps import get_settings
from app.core.logs import show_info
from app.friend_reviews.router import router as friend_reviews_router
from app.heart_tasks.router import router as heart_tasks_router
from app.home.router import router as home_router
from app.matching.router import router as matching_router
from app.me.router import router as me_router
from app.notifications.router import router as notifications_router
from app.profile_onboarding.router import router as profile_onboarding_router
from app.profile_onboarding.startup_check import warn_if_fallback_avatar_missing
from app.profile_onboarding.tasks_router import router as profile_onboarding_tasks_router
from app.referral.router import router as referral_router
from app.safety.router import router as safety_router
from app.school_email.router import router as school_email_router
from app.settings import AdminWebSettings
from app.student_verification.review_hook import router as verification_review_hook_router
from app.student_verification.router import router as student_verification_router

_logger = logging.getLogger(__name__)
# 부팅 한 줄(INFO)이 Cloud Run 로그에 보이게 한다 — core/logs.py.
show_info(_logger)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """설정을 확인하고 HTTP 클라이언트를 하나 만든다(미결 41③).

    **설정을 여기서 한 번 만드는 것이 핵심이다.** `get_settings` 는 `Depends` 로만 불려서,
    이 줄이 없으면 환경변수가 빠진 채로도 컨테이너가 뜨고 `/health` 까지 통과한 뒤
    **첫 요청부터 500** 이 난다. 부팅에서 멈춰야 배포 사고가 배포 때 보인다.

    `async with` 라 프로세스가 내려갈 때 커넥션도 같이 닫힌다 — 꺼내 쓰는 곳은
    `core/deps.py` 의 `get_client` 한 곳뿐이다.
    """
    settings = get_settings()
    # 애플 서명(아이폰 하트 구매 JWS · 탈퇴 때 애플 철회)이 쓰는 부품이 운영 이미지에 들었는지 배포 뒤 이 한 줄로 본다.
    _logger.info("cryptography=%s", cryptography.__version__)
    async with httpx.AsyncClient() as client:
        app.state.http_client = client
        # 기본 아바타 원본 확인(결함 D-02) — 알리기만 하고 부팅을 막지 않는다(예외도 삼킨다).
        await warn_if_fallback_avatar_missing(settings, client)
        yield


# 문서 주소(/docs · /redoc · /openapi.json)는 열지 않는다 — 운영에서 경로 목록 · 요청 모양을 누구에게나 보여 준다
# (2026-10-12 보안 점검 #10). 경로 이름이 필요하면 코드에서 app.openapi() 를 부른다.
app = FastAPI(title="CampusMate Backend", lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)
app.include_router(auth_hooks_router)
app.include_router(consents_router)
app.include_router(school_email_router)
app.include_router(student_verification_router)
app.include_router(verification_review_hook_router)
app.include_router(profile_onboarding_router)
app.include_router(profile_onboarding_tasks_router)
app.include_router(matching_router)
app.include_router(cards_batch_router)
app.include_router(cards_router)
app.include_router(chat_batch_router)
app.include_router(chat_router)
app.include_router(home_router)
app.include_router(notifications_router)
app.include_router(me_router)
app.include_router(safety_router)
app.include_router(community_router)
app.include_router(account_batch_router)
app.include_router(account_router)
app.include_router(referral_router)
app.include_router(friend_reviews_router)
app.include_router(heart_tasks_router)
app.include_router(billing_router)
app.include_router(billing_batch_router)
app.include_router(billing_apple_router)
app.include_router(admin_router)
# 관리자 웹만 CORS 를 탄다. ADMIN_ALLOWED_ORIGINS 가 비면 미들웨어를 붙이지 않고, '*' 면 여기서 멈춰 서버가 뜨지 않는다.
install_admin_cors(app, AdminWebSettings().admin_origins)


@app.exception_handler(httpx.HTTPStatusError)
async def upstream_call_failed(request: Request, exc: httpx.HTTPStatusError) -> JSONResponse:
    """라우터가 잡지 않은 저장소 호출 실패. 그냥 두면 uvicorn 이 "Exception in ASGI application" 에 예외 문구를 찍는데,
    그 문구에는 요청 주소(Supabase 호스트 · 사진 경로)가 통째로 들어 있다(2026-10-12 보안 점검).
    메서드 · 상태 코드 · 예외 이름만 남긴다. 예외 클래스 전용 처리기라 다시 던지지 않는다(Exception · 500 처리기는 다시 던진다)."""
    _logger.error("저장소 호출 실패 %s %s status=%s", type(exc).__name__, exc.request.method, exc.response.status_code)
    return JSONResponse(status_code=500, content={"detail": "Internal Server Error"})


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
