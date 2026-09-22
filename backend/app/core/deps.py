"""라우터가 각자 들고 있던 의존성 제공자를 한 곳에 모은다.

전부 FastAPI 의 `Depends` 로 쓰는 것이라 테스트는 `app.dependency_overrides[<제공자>]` 하나로
목을 끼운다(예전에는 라우터마다 `_client_override` 같은 전역 변수를 뒀다).
"""
from collections.abc import Callable
from functools import lru_cache
from typing import NamedTuple
from uuid import UUID

import httpx
from fastapi import Depends, Header, Request
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


def get_vision_client_factory() -> Callable[[], vision.ImageAnnotatorAsyncClient]:
    """클라이언트가 아니라 "만드는 함수"를 준다.

    학생증 OCR 은 ADC 자격증명 실패(GoogleAuthError)까지 엔드포인트의 try 안에서 잡아
    사람 재검토로 넘긴다 — 의존성이 미리 만들면 그 실패가 500 으로 새어 나간다.
    """
    return get_vision_client


def get_client(request: Request) -> httpx.AsyncClient:
    """앱 전체가 나눠 쓰는 HTTP 클라이언트(Supabase·PostgREST·FCM 호출).

    만드는 것은 lifespan 한 곳이다(main.py, 미결 41③). 요청마다 새로 만들면 커넥션과
    TLS 악수를 매번 다시 한다 — 요청 하나가 PostgREST 를 여러 번 부르는 구조라
    그 손해가 그대로 지연이 된다.

    테스트는 `app.dependency_overrides[get_client]` 로 덮어써 lifespan 을 켜지 않는다.
    """
    return request.app.state.http_client


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
