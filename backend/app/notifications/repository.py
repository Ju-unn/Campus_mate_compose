from datetime import datetime
from uuid import UUID

from app.core.http import raise_for_status
from app.core.postgrest import PostgrestRepository

_COLUMNS = "id,kind,title,body,data,created_at,read_at"


class NotificationRepository(PostgrestRepository):
    """앱 안 알림함(notifications 표) 읽기 · 읽음 처리 · 보관 정리. 쓰기(한 줄 남기기)는 푸시가 지나가는
    CardRepository.insert_notification 이 한다. service_role 이라 RLS 가 없다 — 사람 단위 요청은 모두
    `profile_id=eq.<나>` 를 건다."""

    async def fetch_page(self, profile_id: UUID, limit: int, before: datetime | None) -> list[dict]:
        """최신순. `before` 보다 오래된 것부터 `limit` 줄(부른 쪽이 한 줄 더 달라고 해 다음 쪽 여부를 안다).
        created_at 이 같으면 id 로 가려 순서가 흔들리지 않는다."""
        # ponytail: 다음 쪽 기준이 created_at 하나뿐이라 마이크로초까지 같은 두 줄이 쪽 경계에 걸리면 한 줄이 빠진다.
        # 호출마다 따로 insert 해 거의 없다. 생기면 (created_at, id) 쌍 커서로 바꾼다.
        params = {"profile_id": f"eq.{profile_id}", "select": _COLUMNS,
                  "order": "created_at.desc,id.desc", "limit": limit}
        if before is not None:
            params["created_at"] = f"lt.{before.isoformat()}"
        response = await self._get("notifications", params=params)
        raise_for_status(response)
        return response.json()

    async def count_unread(self, profile_id: UUID) -> int:
        response = await self._client.get(
            f"{self._postgrest_url}/notifications",
            params={"profile_id": f"eq.{profile_id}", "read_at": "is.null", "select": "id", "limit": 1},
            headers=self._with_prefer("count=exact"),
        )
        raise_for_status(response)
        # Content-Range: 0-0/37 (없으면 */0) — 전체 건수는 / 뒤다.
        return int(response.headers["content-range"].rsplit("/", 1)[1])

    async def mark_read(self, profile_id: UUID, notification_id: UUID, now: datetime) -> bool:
        """내 알림이면 읽음으로 찍고 True, 남의 것 · 없는 것이면 False. 이미 읽은 것은 시각을 그대로 두고 True
        (`read_at is null` 조건이라 첫 읽은 시각이 지켜진다)."""
        response = await self._patch(
            "notifications",
            params={"id": f"eq.{notification_id}", "profile_id": f"eq.{profile_id}", "read_at": "is.null",
                    "select": "id"},
            json={"read_at": now.isoformat()}, prefer="return=representation",
        )
        raise_for_status(response)
        if response.json():
            return True
        # 갱신 0행 = 이미 읽었거나 내 것이 아니다. 내 것인지 따로 본다.
        response = await self._get("notifications", params={
            "id": f"eq.{notification_id}", "profile_id": f"eq.{profile_id}", "select": "id", "limit": 1,
        })
        raise_for_status(response)
        return bool(response.json())

    async def mark_all_read(self, profile_id: UUID, now: datetime) -> None:
        response = await self._patch(
            "notifications",
            params={"profile_id": f"eq.{profile_id}", "read_at": "is.null"},
            json={"read_at": now.isoformat()}, prefer="return=minimal",
        )
        raise_for_status(response)

    async def delete_older_than(self, cutoff: datetime) -> int:
        """cutoff 보다 오래된 행을 전부 지우고 지운 줄 수를 돌려준다(배치용, 사람 구분 없음)."""
        # 부모 _delete 는 Prefer 를 못 보내 PostgREST 가 204(본문 없음)를 준다 — 직접 불러 지운 행을 돌려받는다.
        response = await self._client.delete(
            f"{self._postgrest_url}/notifications",
            params={"created_at": f"lt.{cutoff.isoformat()}", "select": "id"},
            headers=self._with_prefer("return=representation"),
        )
        raise_for_status(response)
        return len(response.json())
