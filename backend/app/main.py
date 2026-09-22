from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI

from app.auth_hooks.router import router as auth_hooks_router
from app.cards.batch_router import router as cards_batch_router
from app.cards.router import router as cards_router
from app.chat.batch_router import router as chat_batch_router
from app.chat.router import router as chat_router
from app.core.deps import get_settings
from app.matching.router import router as matching_router
from app.profile_onboarding.router import router as profile_onboarding_router
from app.student_verification.router import router as student_verification_router

@asynccontextmanager
async def lifespan(app: FastAPI):
    """설정을 확인하고 HTTP 클라이언트를 하나 만든다(미결 41③).

    **설정을 여기서 한 번 만드는 것이 핵심이다.** `get_settings` 는 `Depends` 로만 불려서,
    이 줄이 없으면 환경변수가 빠진 채로도 컨테이너가 뜨고 `/health` 까지 통과한 뒤
    **첫 요청부터 500** 이 난다. 부팅에서 멈춰야 배포 사고가 배포 때 보인다.

    `async with` 라 프로세스가 내려갈 때 커넥션도 같이 닫힌다 — 꺼내 쓰는 곳은
    `core/deps.py` 의 `get_client` 한 곳뿐이다.
    """
    get_settings()
    async with httpx.AsyncClient() as client:
        app.state.http_client = client
        yield


app = FastAPI(title="CampusMate Backend", lifespan=lifespan)
app.include_router(auth_hooks_router)
app.include_router(student_verification_router)
app.include_router(profile_onboarding_router)
app.include_router(matching_router)
app.include_router(cards_batch_router)
app.include_router(cards_router)
app.include_router(chat_batch_router)
app.include_router(chat_router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
