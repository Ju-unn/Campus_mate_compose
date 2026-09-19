from fastapi import FastAPI

app = FastAPI(title="CampusMate Backend")


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok"}
