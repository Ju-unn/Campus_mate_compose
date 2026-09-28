from uuid import UUID

from app.core import errors
from app.core.http import raise_for_status
from app.core.postgrest import PostgrestRepository

# 리뷰 한 장과 작성자(닉네임 · 학교 · 아바타). `!inner` + `reviewer.status=eq.active` 로 작성자가
# active 가 아닌(탈퇴 · 정지) 리뷰는 DB 에서 빠진다 — ERD "작성자 탈퇴 시 즉시 숨김".
_REVIEW_SELECT = (
    "id,reviewer_id,tags,comment,created_at,"
    "reviewer:profiles!friend_reviews_reviewer_id_fkey!inner("
    "nickname,status,universities(name),profile_avatars(storage_path,status,created_at))"
)


class FriendReviewRepository(PostgrestRepository):
    """지인 리뷰. 쓰기가 insert 한 번, 읽기가 embed 한 번이라 DB 함수 없이 PostgREST 로 한다."""

    async def _rows(self, path: str, params: dict) -> list[dict]:
        response = await self._get(path, params=params)
        raise_for_status(response)
        return response.json()

    async def fetch_about(self, reviewee: UUID | str) -> list[dict]:
        """받은 리뷰 최신순. 가려진 것 · 작성자가 active 아닌 것은 빠진다. 차단은 부르는 쪽이 거른다.
        ponytail: 페이지 없음 — 받는 수 = 추천으로 이어진 사람 수라 작다. db-max-rows(1000) 넘으면 커서로."""
        return await self._rows("friend_reviews", {
            "reviewee_id": f"eq.{reviewee}", "status": "eq.visible", "reviewer.status": "eq.active",
            "select": _REVIEW_SELECT, "order": "created_at.desc",
        })

    async def is_linked(self, a: UUID | str, b: UUID | str) -> bool:
        """추천으로 이어졌는가(어느 방향이든). referrals 는 온보딩 탭 표 — 행이 있으면 연결이다(09-28 합의)."""
        rows = await self._rows("referrals", {
            "or": f"(and(referee_id.eq.{a},referrer_id.eq.{b}),and(referee_id.eq.{b},referrer_id.eq.{a}))",
            "select": "referee_id", "limit": "1",
        })
        return bool(rows)

    async def has_written(self, reviewer: UUID | str, reviewee: UUID | str) -> bool:
        rows = await self._rows("friend_reviews", {
            "reviewer_id": f"eq.{reviewer}", "reviewee_id": f"eq.{reviewee}", "select": "id",
        })
        return bool(rows)

    async def fetch_target(self, profile_id: UUID | str) -> dict | None:
        """20b 머리에 그릴 것(닉네임 · 아바타)과 active 판정용 status."""
        rows = await self._rows("profiles", {
            "id": f"eq.{profile_id}",
            "select": "id,nickname,status,profile_avatars(storage_path,status,created_at)",
        })
        return rows[0] if rows else None

    async def insert_review(self, row: dict) -> str:
        response = await self._post("friend_reviews", json=row, prefer="return=representation")
        # 23505 = friend_reviews_once — 동시에 두 번 눌러도 한 줄만 남고 나머지는 409.
        raise_for_status(response, conflict_detail=errors.FRIEND_REVIEW_ALREADY_WRITTEN)
        return response.json()[0]["id"]

    async def fetch_for_report(self, review_id: UUID | str) -> dict | None:
        """신고(safety POST /reports)용 — 가려진 것까지 읽고 판단은 부르는 쪽이 한다."""
        rows = await self._rows("friend_reviews", {
            "id": f"eq.{review_id}", "select": "id,reviewer_id,reviewee_id,tags,comment,status,created_at",
        })
        return rows[0] if rows else None
