"""PostgREST 제약 위반을 어떤 상태코드로 바꾸는지(core/http.py)."""
import httpx
import pytest
from fastapi import HTTPException

from app.core import errors
from app.core.http import raise_for_status


def _response(code: str) -> httpx.Response:
    return httpx.Response(400, json={"code": code, "message": code})


def test_duplicate_is_the_only_conflict():
    with pytest.raises(HTTPException) as raised:
        raise_for_status(_response("23505"))

    assert raised.value.status_code == 409
    assert raised.value.detail == errors.ALREADY_REGISTERED


@pytest.mark.parametrize("code", ["23503", "23514", "22P02", "23502"])
def test_bad_input_becomes_422(code):
    """FK 위반(23503)도 여기 들어간다 — 가리키는 행이 없는 것은 충돌이 아니라 잘못된 id 다."""
    with pytest.raises(HTTPException) as raised:
        raise_for_status(_response(code))

    assert raised.value.status_code == 422
    assert raised.value.detail == errors.INVALID_INPUT


def test_plain_409_without_a_code_is_still_a_conflict():
    with pytest.raises(HTTPException) as raised:
        raise_for_status(httpx.Response(409, text="conflict"))

    assert raised.value.status_code == 409


def test_success_passes_through():
    raise_for_status(httpx.Response(200, json=[]))
