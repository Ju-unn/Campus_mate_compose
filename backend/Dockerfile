FROM python:3.12-slim

WORKDIR /app

COPY pyproject.toml ./
RUN pip install --no-cache-dir .

COPY app ./app

# Cloud Run 이 $PORT 로 리스닝 포트를 알려준다 — 하드코딩하지 않는다.
CMD exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}
