import asyncio
import logging
from typing import Literal
from uuid import UUID, uuid4

import httpx
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile

from app.core import errors
from app.core.deps import Caller, get_verified_caller
from app.heart_tasks.repository import HeartTaskRepository
from app.heart_tasks.storage import HeartProofStorage
from app.student_verification.image_validation import MAX_IMAGE_BYTES, student_id_content_type

router = APIRouter()
logger = logging.getLogger(__name__)

# 제출 때 약속하는 하트(DESIGN §8.10, 2026-10-16 사용자 확정 — 에브리타임 50 → 40, 단톡방 25 그대로). 값을 바꾸는 날
# 이 줄만 고친다 — 이미 낸 제출은 줄에 적힌 금액으로 승인된다.
REWARD_HEARTS = {"everytime_post": 40, "kakao_share": 25}
# 투표 보상은 여기서 주지 않는다(DB cast_poll_vote 5하트 · 주 15, 20261016144525). 18a 에 보여 주기만 한다.
POLL_VOTE_REWARD = 5
# 18a 줄 순서(DESIGN §8.10 표).
TASK_ORDER = ("everytime_post", "kakao_share", "poll_vote")
# 인증샷을 내는 항목(투표는 커뮤니티 탭에서 저절로 쌓인다).
PROOF_TASKS = ("everytime_post", "kakao_share")
# 제출 1건당 인증샷 1~3장(대장 결정 2026-10-19). DB check(`heart_task_submissions_paths_max`)와 같은 수.
MAX_PHOTOS = 3
# 18a 검수 대기 목록의 썸네일 서명 URL 유효 시간. 18a 에 들어올 때마다 새로 받는다.
PENDING_URL_TTL_SECONDS = 600


def _state(row: dict) -> str:
    if row["reviewing"]:
        return "reviewing"
    if row["used"] >= row["task_limit"]:
        return "done"
    if row["last_status"] == "rejected":
        return "rejected"
    return "open"


def _task(name: str, row: dict, pending: list[dict] | None = None) -> dict:
    """18a 한 줄. 위 여섯 칸은 옛 앱이 읽는다 — 이름 · 뜻을 바꾸지 않는다(`state` 는 검수 중이 있으면 늘 reviewing).
    아래 세 칸은 새 앱이 읽는다: can_submit(지금 낼 수 있나) · max_photos(한 번에 낼 수 있는 사진 수) · pending(검수 대기 줄)."""
    state = _state(row)
    proof = name in PROOF_TASKS
    return {
        "task": name,
        "reward_hearts": REWARD_HEARTS.get(name, POLL_VOTE_REWARD),
        "state": state,
        "used": row["used"],
        "limit": row["task_limit"],
        # 반려 줄에만 싣는다. 다시 내서 검수 중이 되면 지난 사유는 보이지 않는다.
        "reject_reason": row["last_reject_reason"] if state == "rejected" else None,
        "can_submit": proof and row["used"] < row["task_limit"],
        "max_photos": MAX_PHOTOS if proof else 0,
        "pending": pending or [],
    }


def _repo(caller: Caller) -> HeartTaskRepository:
    return HeartTaskRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)


def _storage(caller: Caller) -> HeartProofStorage:
    return HeartProofStorage(caller.settings.storage_url, caller.settings.supabase_service_role_key, caller.client)


async def _signed_url(storage: HeartProofStorage, path: str) -> str | None:
    """서명에 실패한 사진은 None — 그 한 장만 비고 목록은 그대로 간다. 경로는 로그에 남기지 않는다."""
    try:
        return await storage.create_signed_url(path, PENDING_URL_TTL_SECONDS)
    except (httpx.HTTPError, KeyError, ValueError):
        logger.warning("무료 하트 대기 사진 서명 실패")
        return None


async def _pending_by_task(storage: HeartProofStorage, rows: list[dict]) -> dict[str, list[dict]]:
    """검수 중 줄을 항목별로 묶는다. 사진마다 10분 서명 URL(순서 유지, 실패한 장은 None). 경로 원문은 싣지 않는다."""
    signed = await asyncio.gather(*(
        asyncio.gather(*(_signed_url(storage, path) for path in row["storage_paths"])) for row in rows
    ))
    view: dict[str, list[dict]] = {}
    for row, urls in zip(rows, signed):
        view.setdefault(row["task"], []).append(
            {"id": row["id"], "created_at": row["created_at"], "photo_urls": list(urls)})
    return view


async def _read_proofs(uploads: list[UploadFile]) -> list[tuple[bytes, str]]:
    """사진 1~3장을 읽어 (바이트, Content-Type) 목록으로. 어느 한 장이라도 틀리면 아무것도 올리기 전에 거절한다."""
    if not 1 <= len(uploads) <= MAX_PHOTOS:
        raise HTTPException(status_code=422, detail=errors.INVALID_INPUT)
    proofs = []
    for upload in uploads:
        data = await upload.read(MAX_IMAGE_BYTES + 1)  # 한도를 넘었는지만 알면 된다 — 끝까지 읽지 않는다
        # 앱이 보낸 Content-Type 은 믿지 않는다 — 학생증과 같은 판정(10MB 초과 · jpeg/png 아님 → None).
        content_type = student_id_content_type(data)
        if content_type is None:
            raise HTTPException(status_code=400, detail=errors.PHOTO_UNREADABLE)
        proofs.append((data, content_type))
    return proofs


async def _remove_quietly(storage: HeartProofStorage, paths: list[str], profile_id: UUID, submission_id: UUID) -> None:
    try:
        await storage.delete(paths)
    except httpx.HTTPError:
        # 경로는 남기지 않는다(Global Constraint 6) — 두 id 로 대시보드에서 찾는다.
        logger.warning("무료 하트 인증샷 되돌리기 실패(고아 파일) profile=%s submission=%s", profile_id, submission_id)


async def _upload_all(storage: HeartProofStorage, profile_id: UUID, submission_id: UUID,
                      paths: list[str], proofs: list[tuple[bytes, str]]) -> None:
    """모든 장을 함께 올린다. 하나라도 실패하면 시도한 경로 전부를 지우고(없는 파일 삭제는 오류가 아니다) 그 예외를 올린다."""
    results = await asyncio.gather(
        *(storage.upload(profile_id, submission_id, index, data, content_type)
          for index, (data, content_type) in enumerate(proofs, start=1)),
        return_exceptions=True,
    )
    failures = [result for result in results if isinstance(result, Exception)]
    if failures:
        await _remove_quietly(storage, paths, profile_id, submission_id)
        raise failures[0]


async def _notify_review(webhook_url: str, client: httpx.AsyncClient,
                         submission_id: UUID, profile_id: UUID, task: str, admin_base_url: str) -> None:
    """학생증 재검토와 같은 채널. **번호만** 싣는다 — 사진 · 경로 · 이름은 싣지 않는다(웹훅 기록에 영구히 남는다).
    관리자 웹 주소가 있으면 그 건의 검수 링크(로그인 · 2단계 뒤에만 열린다)를, 없으면 Supabase 대시보드 안내를 붙인다.
    실패를 삼킨다 — 제출은 이미 끝났고, 운영자는 대시보드 목록으로도 본다."""
    where = (f"대시보드: {admin_base_url.rstrip('/')}/heart-tasks/{submission_id}" if admin_base_url
             else "Supabase 대시보드 heart_task_submissions 에서 확인해 주세요.")
    content = f"무료 하트 인증 1건 (제출: {submission_id}, 계정: {profile_id}, 항목: {task}). {where}"
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
    """18a 목록. 세 줄을 늘 같은 순서로. 검수 중인 제출은 항목별 `pending` 에 사진 서명 URL 과 함께 싣는다."""
    repo = _repo(caller)
    rows, pending_rows = await asyncio.gather(repo.fetch_status(caller.profile_id), repo.fetch_pending(caller.profile_id))
    pending = await _pending_by_task(_storage(caller), pending_rows)
    return {"tasks": [_task(name, rows[name], pending.get(name)) for name in TASK_ORDER]}


@router.post("/heart-tasks/{task}/submissions", status_code=201)
async def submit_heart_task(
    task: Literal["everytime_post", "kakao_share"],
    photo: UploadFile | None = File(default=None),
    photos: list[UploadFile] = File(default=[]),
    caller: Caller = Depends(get_verified_caller),
) -> dict:
    """18b 제출. 사진은 `photos` 1~3장(새 앱) 또는 `photo` 한 장(옛 앱) — 둘 다 오면 합쳐 센다(0장 · 4장 이상은 422).
    한도에 찼으면 검수 중이 있을 때 409, 없을 때 429 — 사진을 올리기 전에 먼저 본다(고아 파일을 줄이려고).
    검수 중이어도 한도가 남았으면 낼 수 있다(단톡방은 이어서 제출). 최종 판정은 DB 함수가 사람·항목 락 아래에서
    다시 한다. 그 판정에서 막히면 방금 올린 파일을 전부 지운다."""
    proofs = await _read_proofs([*([photo] if photo else []), *photos])

    repo = _repo(caller)
    before = (await repo.fetch_status(caller.profile_id))[task]
    if before["used"] >= before["task_limit"]:
        if before["reviewing"]:
            raise HTTPException(status_code=409, detail=errors.HEART_TASK_IN_REVIEW)
        raise HTTPException(status_code=429, detail=errors.HEART_TASK_MONTHLY_LIMIT)

    settings = caller.settings
    storage = _storage(caller)
    submission_id = uuid4()
    paths = [storage.proof_path(caller.profile_id, submission_id, index, content_type)
             for index, (_, content_type) in enumerate(proofs, start=1)]
    await _upload_all(storage, caller.profile_id, submission_id, paths, proofs)
    try:
        await repo.submit(submission_id, caller.profile_id, task, paths, REWARD_HEARTS[task])
    except httpx.TransportError:
        # 답을 못 받았다 — 줄이 이미 생겼을 수 있어 파일을 둔다(지우면 사진 없는 "검수 중" 줄에 막힌다).
        # ponytail: 줄이 안 생겼으면 고아 파일(최대 3장) — 탈퇴 정리가 폴더째 지운다. 잦아지면 id 로 줄을 확인하고 지운다.
        logger.warning("무료 하트 제출 응답 없음, 파일 둠 profile=%s submission=%s", caller.profile_id, submission_id)
        raise
    except (HTTPException, httpx.HTTPStatusError):
        # DB 가 답하고 거절했다 = 롤백됐다. 방금 올린 파일을 전부 지운다.
        await _remove_quietly(storage, paths, caller.profile_id, submission_id)
        raise

    await _notify_review(settings.discord_webhook_url, caller.client, submission_id, caller.profile_id, task,
                         settings.admin_base_url)
    after, pending_rows = await asyncio.gather(repo.fetch_status(caller.profile_id), repo.fetch_pending(caller.profile_id))
    pending = await _pending_by_task(storage, pending_rows)
    return {"task": _task(task, after[task], pending.get(task))}
