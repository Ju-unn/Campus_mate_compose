import logging
from typing import Literal
from uuid import UUID, uuid4

import httpx
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile

from app.core import errors
from app.core.deps import Caller, get_verified_caller
from app.heart_tasks.repository import HeartTaskRepository
from app.heart_tasks.storage import HeartProofStorage
from app.student_verification.image_validation import student_id_content_type

router = APIRouter()
logger = logging.getLogger(__name__)

# 제출 때 약속하는 하트(DESIGN §8.10 "초기(~100명)" 값, 계획서 D5). 100명 이후 값(30 · 20)으로 바꾸는 날 이 줄만
# 고친다 — 이미 낸 제출은 줄에 적힌 금액으로 승인된다.
REWARD_HEARTS = {"everytime_post": 50, "kakao_share": 25}
# 투표 보상은 여기서 주지 않는다(DB cast_poll_vote). 18a 에 보여 주기만 한다.
POLL_VOTE_REWARD = 10
# 18a 줄 순서(DESIGN §8.10 표).
TASK_ORDER = ("everytime_post", "kakao_share", "poll_vote")


def _state(row: dict) -> str:
    if row["reviewing"]:
        return "reviewing"
    if row["used"] >= row["task_limit"]:
        return "done"
    if row["last_status"] == "rejected":
        return "rejected"
    return "open"


def _task(name: str, row: dict) -> dict:
    state = _state(row)
    return {
        "task": name,
        "reward_hearts": REWARD_HEARTS.get(name, POLL_VOTE_REWARD),
        "state": state,
        "used": row["used"],
        "limit": row["task_limit"],
        # 반려 줄에만 싣는다. 다시 내서 검수 중이 되면 지난 사유는 보이지 않는다.
        "reject_reason": row["last_reject_reason"] if state == "rejected" else None,
    }


def _repo(caller: Caller) -> HeartTaskRepository:
    return HeartTaskRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)


async def _notify_review(webhook_url: str, client: httpx.AsyncClient,
                         submission_id: UUID, profile_id: UUID, task: str) -> None:
    """학생증 재검토와 같은 채널. **번호만** 싣는다 — 사진 · 경로 · 이름은 싣지 않는다(웹훅 기록에 영구히 남는다).
    실패를 삼킨다 — 제출은 이미 끝났고, 운영자는 대시보드 목록으로도 본다."""
    content = (f"무료 하트 인증 1건 (제출: {submission_id}, 계정: {profile_id}, 항목: {task}). "
               "Supabase 대시보드 heart_task_submissions 에서 확인해 주세요.")
    try:
        response = await client.post(webhook_url, json={"content": content})
    except httpx.HTTPError:
        logger.warning("무료 하트 인증 디스코드 알림 실패 submission=%s", submission_id)
        return
    if not response.is_success:
        # raise_for_status 를 쓰지 않는다 — 그 예외 문구에는 웹훅 주소(토큰 포함)가 통째로 들어간다.
        logger.warning("무료 하트 인증 디스코드 알림 실패 status=%s submission=%s", response.status_code, submission_id)


@router.get("/heart-tasks")
async def list_heart_tasks(caller: Caller = Depends(get_verified_caller)) -> dict:
    """18a 목록. 세 줄을 늘 같은 순서로."""
    rows = await _repo(caller).fetch_status(caller.profile_id)
    return {"tasks": [_task(name, rows[name]) for name in TASK_ORDER]}


@router.post("/heart-tasks/{task}/submissions", status_code=201)
async def submit_heart_task(
    task: Literal["everytime_post", "kakao_share"],
    photo: UploadFile = File(),
    caller: Caller = Depends(get_verified_caller),
) -> dict:
    """18b 제출. 검수 중이면 409, 이번 달 한도면 429 — 둘 다 사진을 올리기 전에 먼저 본다(고아 파일을 줄이려고).
    최종 판정은 DB 함수가 다시 한다. 그 판정에서 막히면 방금 올린 파일을 지운다."""
    data = await photo.read()
    # 앱이 보낸 Content-Type 은 믿지 않는다 — 학생증과 같은 판정(10MB 초과 · jpeg/png 아님 → None).
    content_type = student_id_content_type(data)
    if content_type is None:
        raise HTTPException(status_code=400, detail=errors.PHOTO_UNREADABLE)

    repo = _repo(caller)
    before = (await repo.fetch_status(caller.profile_id))[task]
    if before["reviewing"]:
        raise HTTPException(status_code=409, detail=errors.HEART_TASK_IN_REVIEW)
    if before["used"] >= before["task_limit"]:
        raise HTTPException(status_code=429, detail=errors.HEART_TASK_MONTHLY_LIMIT)

    settings = caller.settings
    storage = HeartProofStorage(settings.storage_url, settings.supabase_service_role_key, caller.client)
    submission_id = uuid4()
    path = await storage.upload(caller.profile_id, submission_id, data, content_type)
    try:
        await repo.submit(submission_id, caller.profile_id, task, path, REWARD_HEARTS[task])
    except httpx.TransportError:
        # 답을 못 받았다 — 줄이 이미 생겼을 수 있어 파일을 둔다(지우면 사진 없는 "검수 중" 줄에 막힌다).
        # ponytail: 줄이 안 생겼으면 고아 파일 — 탈퇴 정리가 폴더째 지운다. 잦아지면 id 로 줄을 확인하고 지운다.
        logger.warning("무료 하트 제출 응답 없음, 파일 둠 profile=%s submission=%s", caller.profile_id, submission_id)
        raise
    except (HTTPException, httpx.HTTPStatusError):
        # DB 가 답하고 거절했다 = 롤백됐다. 방금 올린 파일을 지운다.
        try:
            await storage.delete([path])
        except httpx.HTTPError:
            # 경로는 남기지 않는다(Global Constraint 6) — 두 id 로 대시보드에서 찾는다.
            logger.warning("무료 하트 인증샷 되돌리기 실패(고아 파일) profile=%s submission=%s",
                           caller.profile_id, submission_id)
        raise

    await _notify_review(settings.discord_webhook_url, caller.client, submission_id, caller.profile_id, task)
    after = await repo.fetch_status(caller.profile_id)
    return {"task": _task(task, after[task])}
