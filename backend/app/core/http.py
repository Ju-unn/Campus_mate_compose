"""PostgREST 응답을 다루는 공용 코드.

원래 profile_onboarding.repository 안에 있었고 cards·matching 저장소가 밑줄 붙은 이름을
건너서 import 하고 있었다 — 공용이면 공용 자리에 둔다.
"""
import httpx
from fastapi import HTTPException

from app.core import errors

# PostgREST 는 Postgres 오류 코드를 그대로 돌려준다. 제약 위반이 500 으로 새어 나가지 않게
# 여기 한 곳에서 4xx 로 바꾼다(2026-09-20 리뷰 필수 2②).
# 23505 = 중복(이미 있는 것) 만 409 다. 나머지는 "보낸 값이 틀렸다" 라서 422 로 묶는다 —
# 23503 = FK 위반(없는 대학·없는 프로필을 가리킴), 23514 = check 위반, 22P02 = 형식 오류,
# 23502 = not null 위반.
# 23503 은 2026-09-22 까지 409 였다. 가리키는 행이 없는 것은 충돌이 아니라 잘못된 id 인데
# "이미 등록된 정보예요" 가 나갔다 — 조각 6 신고(사라진 프로필을 가리킬 수 있다)에서 그대로
# 사용자에게 보일 문구라 지금 바로잡는다.
_CONSTRAINT_STATUS = {"23505": 409, "23503": 422, "23514": 422, "22P02": 422, "23502": 422}


def _error_code(response: httpx.Response) -> str | None:
    try:
        body = response.json()
    except ValueError:
        return None
    return body.get("code") if isinstance(body, dict) else None


def raise_for_status(response: httpx.Response, conflict_detail: str = errors.ALREADY_REGISTERED) -> None:
    if response.status_code < 400:
        return
    # 코드가 없어도 PostgREST 가 409 로 답했으면 중복 충돌로 본다.
    status = _CONSTRAINT_STATUS.get(_error_code(response) or "")
    if status is None and response.status_code == 409:
        status = 409
    if status == 409:
        raise HTTPException(status_code=409, detail=conflict_detail)
    if status == 422:
        raise HTTPException(status_code=422, detail=errors.INVALID_INPUT)
    response.raise_for_status()
