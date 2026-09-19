from fastapi import FastAPI

from app.auth_hooks.router import router as auth_hooks_router

app = FastAPI(title="CampusMate Backend")
app.include_router(auth_hooks_router)


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok"}
