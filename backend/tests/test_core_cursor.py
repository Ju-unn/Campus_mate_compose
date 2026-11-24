"""(시각, id) 커서 짝 검사(core/cursor.py) — 커뮤니티 피드 · 댓글 · 공지 목록 · 관리자 공지 목록이 같이 쓴다."""
from datetime import datetime, timezone
from uuid import UUID

import pytest
from fastapi import HTTPException

from app.core import errors
from app.core.cursor import check_cursor

AT = datetime(2026, 11, 24, tzinfo=timezone.utc)
ID = UUID("44444444-4444-4444-4444-444444444444")


@pytest.mark.parametrize(("before", "before_id"), [(None, None), (AT, ID)])
def test_both_or_neither_is_fine(before, before_id):
    check_cursor(before, before_id)


@pytest.mark.parametrize(("before", "before_id"), [(AT, None), (None, ID)])
def test_only_one_half_is_422(before, before_id):
    with pytest.raises(HTTPException) as caught:
        check_cursor(before, before_id)

    assert (caught.value.status_code, caught.value.detail) == (422, errors.INVALID_INPUT)
