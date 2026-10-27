"""관리자 매칭 현황(설계 10-18 §8-4c)의 DB 호출. 전부 읽기 전용 DB 함수다(마이그레이션 20261018150000, service_role 만 execute).
pairs 의 필터 값은 PostgREST 필터가 아니라 함수의 타입 있는 인자(고정 글자 · uuid · timestamptz)로만 간다."""
from app.admin.repository import AdminRepository


class AdminMatchingRepository(AdminRepository):

    async def summary(self) -> dict:
        """수락 · 수락한 사람 · 매칭 · 카톡 공유 쌍 숫자 한 줄."""
        return (await self._rpc("admin_matching_summary", {}))[0]

    async def daily(self, days: int) -> list[dict]:
        """한국 시간 하루 단위 [{day, accept_count, match_count, share_count}] 오래된 순, 정확히 days 줄."""
        return await self._rpc("admin_matching_daily", {"p_days": days})

    async def pairs(self, status: str | None, university: str | None, before: tuple[str, str] | None, limit: int) -> list[dict]:
        """누가 누구랑 — 최근 순. before = (matched_at, match_id) 커서, limit 줄을 그대로 요청한다(부르는 쪽이 한 줄 더 달라고 한다).
        함수가 돌려주는 칸에는 사진 · 카톡 아이디 · 대화가 없다."""
        at, last_id = before if before else (None, None)
        return await self._rpc("admin_matching_pairs", {
            "p_status": status, "p_university": university, "p_before_at": at, "p_before_id": last_id, "p_limit": limit,
        })

    async def requests(self, status: str | None, before: tuple[str, str] | None, limit: int) -> list[dict]:
        """누가 누구에게 대화를 신청했나(마이그레이션 20261027100000) — 최근 순. before = (requested_at, card_id) 커서, limit 은 pairs 와 같다.
        함수가 돌려주는 칸에는 사진 · 카톡 아이디 · 대화가 없다."""
        at, last_id = before if before else (None, None)
        return await self._rpc("admin_matching_requests", {"p_status": status, "p_before_at": at, "p_before_id": last_id, "p_limit": limit})
