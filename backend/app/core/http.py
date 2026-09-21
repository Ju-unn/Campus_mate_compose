"""PostgREST 응답을 다루는 공용 코드.

원래 profile_onboarding.repository 안에 있었고 cards·matching 저장소가 밑줄 붙은 이름을
건너서 import 하고 있었다 — 공용이면 공용 자리에 둔다.

백로그: httpx.AsyncClient 를 lifespan 에서 하나 만들어 공유하는 일도 여기로 온다.
지금은 라우터마다 요청 때 새로 만든다(동작에는 문제가 없고, 연결 재사용만 손해다).
"""
import httpx
from fastapi import HTTPException

# PostgREST 는 Postgres 오류 코드를 그대로 돌려준다. 제약 위반이 500 으로 새어 나가지 않게
# 여기 한 곳에서 4xx 로 바꾼다(2026-09-20 리뷰 필수 2②).
# 23503 = FK 위반(없는 대학·없는 프로필을 가리킴), 23502 = not null 위반.
_CONSTRAINT_STATUS = {"23505": 409, "23503": 409, "23514": 422, "22P02": 422, "23502": 422}


def _error_code(response: httpx.Response) -> str | None:
    try:
        body = response.json()
    except ValueError:
        return None
    return body.get("code") if isinstance(body, dict) else None


def raise_for_status(response: httpx.Response, conflict_detail: str = "이미 등록된 정보예요") -> None:
    if response.status_code < 400:
        return
    # 코드가 없어도 PostgREST 가 409 로 답했으면 중복 충돌로 본다.
    status = _CONSTRAINT_STATUS.get(_error_code(response) or "")
    if status is None and response.status_code == 409:
        status = 409
    if status == 409:
        raise HTTPException(status_code=409, detail=conflict_detail)
    if status == 422:
        raise HTTPException(status_code=422, detail="입력한 값을 다시 확인해 주세요")
    response.raise_for_status()
