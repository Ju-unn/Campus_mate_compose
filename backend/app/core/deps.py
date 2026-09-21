"""라우터가 각자 들고 있던 의존성 제공자를 한 곳에 모은다.

전부 FastAPI 의 `Depends` 로 쓰는 것이라 테스트는 `app.dependency_overrides[<제공자>]` 하나로
목을 끼운다(예전에는 라우터마다 `_client_override` 같은 전역 변수를 뒀다).
"""
from functools import lru_cache
from typing import NamedTuple
from uuid import UUID

import httpx
from fastapi import Depends, Header
from google.cloud import vision

from app.settings import Settings
from app.student_verification.current_user import get_current_user_id, get_verified_user_id


@lru_cache
def get_settings() -> Settings:
    return Settings()


@lru_cache
def get_vision_client() -> vision.ImageAnnotatorAsyncClient:
    # ADC 로 인증하므로 인자가 없다. 만드는 값이 비싸 프로세스당 하나만 둔다.
    return vision.ImageAnnotatorAsyncClient()


def get_client() -> httpx.AsyncClient:
    """요청 한 건이 쓰는 HTTP 클라이언트(Supabase·PostgREST·FCM 호출).

    백로그: lifespan 에서 하나 만들어 공유하기(core/http.py 참고). 지금은 요청마다 새로 만든다.
    """
    return httpx.AsyncClient()


class Caller(NamedTuple):
    """엔드포인트마다 똑같이 반복되던 세 줄 — 설정 · HTTP 클라이언트 · 본인 확인이 끝난 profile_id."""

    settings: Settings
    client: httpx.AsyncClient
    profile_id: UUID


async def get_caller(
    authorization: str | None = Header(default=None),
    settings: Settings = Depends(get_settings),
    client: httpx.AsyncClient = Depends(get_client),
) -> Caller:
    """로그인만 확인한다 — 학생증 관문 앞(조각 1b)의 엔드포인트가 쓴다."""
    return Caller(settings, client, await get_current_user_id(settings, client, authorization))


async def get_verified_caller(
    authorization: str | None = Header(default=None),
    settings: Settings = Depends(get_settings),
    client: httpx.AsyncClient = Depends(get_client),
) -> Caller:
    """학생증 인증과 학과 입력까지 끝낸 사용자만 통과시킨다(관문은 current_user.py 에 그대로 있다)."""
    return Caller(settings, client, await get_verified_user_id(settings, client, authorization))
