from fastapi import FastAPI

from app.auth_hooks.router import router as auth_hooks_router
from app.matching.router import router as matching_router
from app.profile_onboarding.router import router as profile_onboarding_router
from app.student_verification.router import router as student_verification_router

app = FastAPI(title="CampusMate Backend")
app.include_router(auth_hooks_router)
app.include_router(student_verification_router)
app.include_router(profile_onboarding_router)
app.include_router(matching_router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
