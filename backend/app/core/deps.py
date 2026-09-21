"""라우터 다섯 곳이 각자 들고 있던 의존성 제공자를 한 곳에 모은다.

`@lru_cache` 라서 프로세스당 하나만 만들어지고, 테스트는 예전처럼
`monkeypatch.setattr(<라우터 모듈>, "get_settings", ...)` 로 라우터가 import 한 이름을 바꿔 치운다.
"""
from functools import lru_cache

from google.cloud import vision

from app.settings import Settings


@lru_cache
def get_settings() -> Settings:
    return Settings()


@lru_cache
def get_vision_client() -> vision.ImageAnnotatorAsyncClient:
    # ADC 로 인증하므로 인자가 없다. 만드는 값이 비싸 프로세스당 하나만 둔다.
    return vision.ImageAnnotatorAsyncClient()
