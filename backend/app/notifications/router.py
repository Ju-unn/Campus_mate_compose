from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query

from app.core.deps import Caller, get_now, get_verified_caller
from app.notifications.repository import NotificationRepository

router = APIRouter()

# ponytail: errors.py 는 공유 파일이라 건드리지 않고 문구를 여기 둔다. 다른 라우터처럼 errors 로 옮기려면 한 줄이다.
NOTIFICATION_NOT_FOUND = "알림을 찾을 수 없어요"


def _repo(caller: Caller) -> NotificationRepository:
    settings, client, _ = caller
    return NotificationRepository(settings.postgrest_url, settings.supabase_service_role_key, client)


def _parse_before(value: str | None) -> datetime | None:
    if value is None:
        return None
    # 인코딩 없이 붙인 `+09:00` 의 `+` 는 쿼리에서 공백이 되어 들어온다 — 되돌려 읽는다.
    try:
        parsed = datetime.fromisoformat(value.strip().replace(" ", "+"))
    except ValueError:
        raise HTTPException(status_code=422, detail="before 는 ISO 시각이어야 해요")
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def _item(row: dict) -> dict:
    return {"id": row["id"], "kind": row["kind"], "title": row["title"], "body": row["body"],
            "data": row["data"], "created_at": row["created_at"], "read": row["read_at"] is not None}


@router.get("/notifications")
async def list_notifications(
    limit: int = Query(30, ge=1, le=100),
    before: str | None = Query(None),
    caller: Caller = Depends(get_verified_caller),
) -> dict:
    """홈 종 알림함 목록. 최신순이고, 다음 쪽은 `next_before` 를 그대로 `before` 에 넣어 부른다(없으면 끝)."""
    before_at = _parse_before(before)
    repo, profile_id = _repo(caller), caller.profile_id
    # 한 줄 더 읽어 다음 쪽이 있는지 안다 — 딱 맞게 끝나는 쪽에 빈 다음 쪽을 약속하지 않는다.
    rows = await repo.fetch_page(profile_id, limit + 1, before_at)
    page = rows[:limit]
    return {
        "items": [_item(row) for row in page],
        "unread_count": await repo.count_unread(profile_id),
        "next_before": page[-1]["created_at"] if len(rows) > limit else None,
    }


@router.get("/notifications/unread-count")
async def get_unread_count(caller: Caller = Depends(get_verified_caller)) -> dict:
    """종 배지용. 행은 내려받지 않고 개수만 센다."""
    return {"unread_count": await _repo(caller).count_unread(caller.profile_id)}


@router.post("/notifications/read-all")
async def read_all(caller: Caller = Depends(get_verified_caller), now: datetime = Depends(get_now)) -> dict:
    await _repo(caller).mark_all_read(caller.profile_id, now)
    return {"unread_count": 0}


@router.post("/notifications/{notification_id}/read")
async def read_one(
    notification_id: UUID,
    caller: Caller = Depends(get_verified_caller),
    now: datetime = Depends(get_now),
) -> dict:
    """남의 것 · 없는 것은 404(존재 여부를 알려 주지 않는다). 이미 읽은 것은 200 으로 멱등이다."""
    if not await _repo(caller).mark_read(caller.profile_id, notification_id, now):
        raise HTTPException(status_code=404, detail=NOTIFICATION_NOT_FOUND)
    return {"read": True}
