"""Cloud Tasks 가 부르는 아바타 생성 워커.

**사람이 부르는 라우터와 파일을 나눈다** — `cards/batch_router.py` · `chat/batch_router.py` 와 같은
관례다. 인증이 통째로 다르고(로그인 토큰 vs 구글 ID 토큰), 한 파일에 섞으면 의존성을 잘못 붙이기 쉽다.
"""
import logging
from uuid import UUID

import httpx
from fastapi import APIRouter, Depends, Header
from openai import AsyncOpenAI
from pydantic import BaseModel

from app.core.batch_auth import verify_oidc_token
from app.core.deps import get_client, get_settings
from app.profile_onboarding.avatars import AvatarGenerator, apply_fallback_avatar
from app.profile_onboarding.repository import ProfileOnboardingRepository

# 사람용 라우터의 제공자를 그대로 쓴다 — 테스트가 목을 끼우는 자리가 하나여야 한다.
from app.profile_onboarding.router import get_openai
from app.profile_onboarding.storage import AvatarStorage, ProfilePhotoStorage
from app.settings import Settings

router = APIRouter()
_logger = logging.getLogger(__name__)


class AvatarTaskRequest(BaseModel):
    profile_id: UUID
    attempt_id: UUID


@router.post("/tasks/avatar-generate")
async def generate_avatar_task(
    body: AvatarTaskRequest,
    authorization: str | None = Header(default=None),
    settings: Settings = Depends(get_settings),
    client: httpx.AsyncClient = Depends(get_client),
    openai_client: AsyncOpenAI = Depends(get_openai),
) -> dict:
    """그림 한 장을 만들어 기록한다. **무슨 일이 있어도 200 이다.**

    생성 실패도 우리에겐 정상 처리다 — 5xx 를 돌려주면 큐가 재시도 대상으로 보고, 그러면 우리가 직접
    세는 5회 카운트와 겹친다. 큐 설정(`--max-attempts=1`)과 코드 양쪽에서 막는다.

    순서는 (1) 행 잡기 -> (2) 카운트 -> (3) 생성 -> (4) 기록이고, **하트 이중 지급을 막는 관문은 (4)** 다.
    """
    await verify_oidc_token(
        authorization,
        audience=settings.avatar_worker_url,
        service_account_email=settings.avatar_tasks_service_account,
    )
    repo = ProfileOnboardingRepository(
        settings.postgrest_url, settings.supabase_service_role_key, client
    )

    # (1) 유료 호출을 아끼는 빠른 관문이다. 240초에 끊겼다가 늦게 깨어난 워커가, 이미 10분 정리로
    #     failed 가 된 행을 되살리면 안 된다. 읽기만 한다 — 여기서 상태를 바꾸면 (4) 의 pending
    #     조건이 늘 0행이 되어 진짜 관문이 사라진다.
    attempt = await repo.fetch_avatar_attempt(body.attempt_id)
    if attempt is None or attempt["status"] != "pending":
        return {"status": "skipped"}

    # (2) **카운트는 생성하기 전에 센다.** AvatarGenerator 는 넘겨받은 값에 +1 을 해서 5회를 판정한다
    #     — 이번 행을 failed 로 바꾼 뒤에 세면 그 행이 이중으로 잡혀 4회째에 보상이 나간다.
    recent_failures = await repo.count_recent_consecutive_avatar_failures(body.profile_id)

    source_path = await repo.fetch_avatar_source_photo_path(body.profile_id)
    if source_path is None:
        # 만드는 사이에 원본 사진을 뺐다. 재료가 없으니 실패로 적고 끝낸다.
        await repo.update_avatar_attempt(body.attempt_id, body.profile_id, "failed", None)
        return {"status": "failed"}

    source_photo = await ProfilePhotoStorage(
        settings.storage_url, settings.supabase_service_role_key, client
    ).download(source_path)
    storage = AvatarStorage(settings.storage_url, settings.supabase_service_role_key, client)
    # (3) 화풍 지시문과 생성기는 그대로 재사용한다 — 옮기는 것은 부르는 자리뿐이다.
    result = await AvatarGenerator(
        openai_client, storage, failure_counts={str(body.profile_id): recent_failures}
    ).generate(str(body.profile_id), source_photo)

    # (4) **진짜 관문.** 만드는 중인 행만 고치고 고쳐진 행 수를 그 자리에서 본다. 0행이면 생성하는
    #     60초 사이에 POST 가 이 행을 정리하고 먼저 보상했다는 뜻이다(`queues pause` 를 오래 걸면 흔하다).
    #     여기서 안 보면 하트가 두 번 나간다. (1) 은 생성 **전**의 사진일 뿐이다.
    updated = await repo.update_avatar_attempt(
        body.attempt_id, body.profile_id, result.status, result.storage_path
    )
    if updated == 0:
        if result.status == "ready":
            # 올려 둔 그림은 아무도 안 쓰는 고아가 된다. 지우러 가지 않는다 — 드물고, 지우다 실패하면
            # 워커만 복잡해진다. 사람이 찾을 수 있게 경로만 남긴다.
            _logger.warning(
                "아바타를 만들었지만 기록할 행이 없다 — 고아 그림으로 둔다 profile_id=%s storage_path=%s",
                body.profile_id, result.storage_path,
            )
        return {"status": "skipped"}

    if result.status == "failed" and result.is_final_failure:
        # 5회째다. 마지막 실패 행은 그대로 두고 보상 행을 따로 넣는다(이력이 남는다).
        await apply_fallback_avatar(repo, storage, settings, client, body.profile_id)
        return {"status": "fallback"}
    return {"status": result.status}
