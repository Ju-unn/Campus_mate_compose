from datetime import datetime
from uuid import UUID

from app.core import errors
from app.core.http import raise_for_status
from app.core.postgrest import PostgrestRepository

# 차단 목록(16f)은 한 번에 다 준다. PostgREST db-max-rows 에 조용히 잘리지 않게 상한을 우리가 정한다
# (chat `_CONVERSATION_LIMIT` 과 같은 이유).
BLOCK_LIST_LIMIT = 200


class SafetyRepository(PostgrestRepository):
    """조각 6 의 두 테이블(blocks · reports)의 출입구. 둘 다 클라이언트는 읽지도 못한다(설계 §7.2)."""

    async def _rows(self, path: str, params: dict) -> list[dict]:
        response = await self._get(path, params=params)
        raise_for_status(response)
        return response.json()

    # 차단 -------------------------------------------------------------------
    async def insert_block(self, blocker_id: UUID | str, blocked_id: UUID | str) -> None:
        """이미 있으면 조용히 성공(on conflict do nothing) — 재시도와 '신고 = 차단' 이 두 번 불러도 안전하다."""
        response = await self._post(
            "blocks", json={"blocker_id": str(blocker_id), "blocked_id": str(blocked_id)},
            params={"on_conflict": "blocker_id,blocked_id"},
            prefer="resolution=ignore-duplicates,return=minimal",
        )
        raise_for_status(response)

    async def delete_block(self, blocker_id: UUID | str, blocked_id: UUID | str) -> None:
        """없어도 성공이다. 대화는 복구하지 않는다(16f) — left_at 은 건드리지 않는다."""
        response = await self._delete("blocks", params={
            "blocker_id": f"eq.{blocker_id}", "blocked_id": f"eq.{blocked_id}",
        })
        raise_for_status(response)

    async def fetch_blocks(self, blocker_id: UUID | str) -> list[dict]:
        """내가 막은 사람 + 닉네임 · 아바타. blocks 는 profiles 를 두 번 가리켜서(blocker · blocked)
        어느 쪽을 붙일지 FK 칸 이름으로 짚어 준다. 실사진은 가져오지 않는다."""
        return await self._rows("blocks", {
            "blocker_id": f"eq.{blocker_id}",
            "select": "blocked_id,created_at,"
                      "profile:profiles!blocked_id(nickname,profile_avatars(storage_path,status,created_at))",
            "order": "created_at.desc",
            "limit": BLOCK_LIST_LIMIT,
        })

    # 신고 -------------------------------------------------------------------
    async def fetch_snapshot_profile(self, profile_id: UUID | str) -> dict:
        """신고 스냅샷 재료. 실명 · 연락처는 가져오지 않는다."""
        return (await self._rows("profiles", {
            "id": f"eq.{profile_id}",
            "select": "nickname,bio,profile_avatars(storage_path,status,created_at)",
        }) or [{}])[0]

    async def count_recent_reports(self, reporter_id: UUID | str, since: datetime, cap: int) -> int:
        """since 이후 내가 넣은 신고 수. 상한(cap)까지만 센다 — 넘었는지만 알면 된다."""
        return len(await self._rows("reports", {
            "reporter_id": f"eq.{reporter_id}", "created_at": f"gte.{since.isoformat()}",
            "select": "id", "limit": cap,
        }))

    async def insert_report(self, report: dict) -> str:
        """새 신고의 id. 같은 사람이 같은 대상을 두 번 신고하면 409 "이미 신고한 사용자예요"
        (unique reports_once_per_reporter → 23505)."""
        response = await self._post("reports", json=report, prefer="return=representation")
        raise_for_status(response, conflict_detail=errors.ALREADY_REPORTED)
        return response.json()[0]["id"]

    async def count_open_reporters(self, target_profile_id: UUID | str) -> int:
        """아직 처리되지 않은(open) 신고의 서로 다른 신고자 수. 운영자가 dismissed 로 닫고 가림을 풀면
        그 신고들은 빠진다 — 해제 뒤 한 건에 바로 다시 가려지지 않게(Ruling 9).
        신고자가 탈퇴해 reporter_id 가 비면(on delete set null) 누구인지 몰라 세지 않는다."""
        rows = await self._rows("reports", {
            "target_profile_id": f"eq.{target_profile_id}", "status": "eq.open", "select": "reporter_id",
        })
        return len({row["reporter_id"] for row in rows if row["reporter_id"]})

    async def auto_hide(self, profile_id: UUID | str, now: datetime) -> bool:
        """auto_hidden_at 이 비어 있을 때만 찍는다. 이번에 찍었으면 True — 디스코드 ② 를 한 번만 보낸다."""
        response = await self._patch(
            "profiles", params={"id": f"eq.{profile_id}", "auto_hidden_at": "is.null", "select": "id"},
            json={"auto_hidden_at": now.isoformat()}, prefer="return=representation",
        )
        raise_for_status(response)
        return bool(response.json())
