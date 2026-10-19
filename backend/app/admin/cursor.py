"""관리자 목록의 쪽 나누기 커서 `{시각}|{id}` 읽기(작업 기록 · 매칭 목록이 같이 쓴다). 시각 · UUID 로 읽히는 것만 받는다 —
필터 문법(쉼표 · 괄호)이 끼어들 수 없게. 틀리면 입력을 되돌리지 않는 422 다(FastAPI 기본 422 는 입력값을 싣는다)."""
import re
from datetime import datetime
from uuid import UUID

from fastapi import HTTPException

from app.core import errors


# PostgREST 가 돌려주는 모양 그대로(YYYY-MM-DDTHH:MM:SS(.ffffff)(±HH:MM|Z)). datetime.fromisoformat 은 ISO 주차(2026-W42-1T…) ·
# 날짜만 · 기본 꼴도 받아 주지만 DB(timestamptz)가 그것을 못 읽어 500 이 났다 — 모양을 먼저 좁힌다.
_TIME = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})", re.ASCII)  # ASCII: 다른 문자 체계의 숫자를 \d 가 받지 않게


def bad() -> HTTPException:
    return HTTPException(status_code=422, detail=errors.INVALID_INPUT)


def parse(value: str) -> tuple[str, str]:
    """`{created_at}|{id}` → (created_at, id)."""
    at, _, last_id = value.partition("|")
    if not _TIME.fullmatch(at):
        raise bad()
    try:
        datetime.fromisoformat(at)
        # UUID() 는 {…} · urn:uuid: · 하이픈 없는 꼴도 받는다 — 필터에는 표준 하이픈 꼴로 다시 써서 넣는다.
        normalised = str(UUID(last_id))
    except ValueError:
        raise bad()
    return at, normalised
