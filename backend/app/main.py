from fastapi import FastAPI

from app.auth_hooks.router import router as auth_hooks_router
from app.cards.batch_router import router as cards_batch_router
from app.cards.router import router as cards_router
from app.chat.batch_router import router as chat_batch_router
from app.chat.router import router as chat_router
from app.matching.router import router as matching_router
from app.profile_onboarding.router import router as profile_onboarding_router
from app.student_verification.router import router as student_verification_router

app = FastAPI(title="CampusMate Backend")
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
