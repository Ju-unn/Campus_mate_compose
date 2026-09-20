import base64
import logging
from dataclasses import dataclass
from typing import Literal
from uuid import uuid4

from openai import AsyncOpenAI

_logger = logging.getLogger(__name__)

# "5회 연속 실패 → 기본 아바타+하트10"(project_slice2_decisions_2026-09-19). SDK 자체 재시도는 끄고
# (max_retries=0, get_openai_client 참고) 이 숫자는 우리 코드가 직접 센다 — SDK 재시도와 겹치면 안 된다
# (2026-09-20 사용자 결정).
MAX_CONSECUTIVE_FAILURES = 5


@dataclass(frozen=True)
class AvatarResult:
    status: Literal["ready", "failed"]
    storage_path: str | None
    is_final_failure: bool = False


class AvatarGenerator:
    """실패 횟수는 프로세스 안 dict 로 세지 않고 profile_avatars 테이블의 최근 연속 failed 행 개수로
    센다(재배포·다중 인스턴스에도 카운트가 유지되도록) — 아래 failure_counts 인자는 그 카운트를 호출부가
    미리 조회해 넘겨주는 자리다(테스트를 위한 의존성 주입, 실제 조회는 avatars_repository.py 몫)."""

    def __init__(self, openai_client: AsyncOpenAI, storage, failure_counts: dict[str, int]):
        self._openai_client = openai_client
        self._storage = storage
        self._failure_counts = failure_counts

    async def generate(self, profile_id: str, source_photo_bytes: bytes) -> AvatarResult:
        try:
            response = await self._openai_client.images.edit(
                model="gpt-image-1",
                image=source_photo_bytes,
                prompt=(
                    "Turn this photo into a soft, friendly cartoon avatar illustration, "
                    "keeping the same hairstyle and general look, no text, no watermark."
                ),
            )
            image_bytes = base64.b64decode(response.data[0].b64_json)
        except Exception:
            _logger.exception("아바타 생성 실패 — profile_id=%s", profile_id)
            self._failure_counts[profile_id] = self._failure_counts.get(profile_id, 0) + 1
            is_final = self._failure_counts[profile_id] >= MAX_CONSECUTIVE_FAILURES
            return AvatarResult(status="failed", storage_path=None, is_final_failure=is_final)

        self._failure_counts[profile_id] = 0
        path = f"{profile_id}/{uuid4()}.png"
        storage_path = await self._storage.upload(path, image_bytes, "image/png")
        return AvatarResult(status="ready", storage_path=storage_path)


def get_openai_client(api_key: str) -> AsyncOpenAI:
    # max_retries=0 — SDK 자체 재시도를 끄고, 실패 카운트는 AvatarGenerator 가 직접 센다(2026-09-20 결정).
    return AsyncOpenAI(api_key=api_key, max_retries=0)
