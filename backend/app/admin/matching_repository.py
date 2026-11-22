"""관리자 매칭 현황(설계 10-18 §8-4c)의 DB 호출. 전부 읽기 전용 DB 함수다(마이그레이션 20261018150000, service_role 만 execute).
pairs 의 필터 값은 PostgREST 필터가 아니라 함수의 타입 있는 인자(고정 글자 · uuid · timestamptz)로만 간다."""
import logging

from app.admin.repository import AdminRepository

logger = logging.getLogger(__name__)

# DB 함수 한 번에 받는 줄 수 상한(함수의 p_limit 검사 1~101).
CHUNK = 101
# 이어 읽기 횟수 상한(약 2만 줄) — 넘으면 경고를 남기고 그때까지 읽은 줄로 쪽을 만든다(쪽 보기가 끝없이 길어지지 않게).
MAX_CHUNKS = 200


class AdminMatchingRepository(AdminRepository):

    async def summary(self) -> dict:
        """수락 · 수락한 사람 · 매칭 · 카톡 공유 쌍 숫자 한 줄."""
        return (await self._rpc("admin_matching_summary", {}))[0]

    async def daily(self, days: int) -> list[dict]:
        """한국 시간 하루 단위 [{day, accept_count, match_count, share_count}] 오래된 순, 정확히 days 줄."""
        return await self._rpc("admin_matching_daily", {"p_days": days})

    async def pairs(self, status: str | None, university: str | None) -> list[dict]:
        """누가 누구랑 — 최근 순 전부(번호 쪽 · 전체 건수는 부르는 쪽이 자른다). 함수가 돌려주는 칸에는 사진 · 카톡 아이디 · 대화가 없다."""
        return await self._every("admin_matching_pairs", {"p_status": status, "p_university": university}, "matched_at", "match_id")

    async def requests(self, status: str | None) -> list[dict]:
        """누가 누구에게 대화를 신청했나(마이그레이션 20261027100000) — 최근 순 전부. 함수가 돌려주는 칸에는 사진 · 카톡 아이디 · 대화가 없다."""
        return await self._every("admin_matching_requests", {"p_status": status}, "requested_at", "card_id")

    async def _every(self, name: str, body: dict, at_key: str, id_key: str) -> list[dict]:
        """커서 DB 함수를 CHUNK 줄씩 끝까지 이어 읽는다(덜 찬 쪽이 오면 끝) — DB 함수를 바꾸지 않고 번호 쪽과 전체 건수를 낸다.
        shortcut: 쪽을 볼 때마다 전부 읽는다(매칭 수 / 101 번 호출) — 수천 건을 넘어 느려지면 offset · 건수를 받는 DB 함수로 바꾼다."""
        rows: list[dict] = []
        for _ in range(MAX_CHUNKS):
            last = rows[-1] if rows else None
            chunk = await self._rpc(name, {**body, "p_before_at": last and last[at_key], "p_before_id": last and last[id_key],
                                           "p_limit": CHUNK})
            rows += chunk
            if len(chunk) < CHUNK:
                return rows
        logger.warning("매칭 목록 이어 읽기 상한 도달 함수=%s 줄=%s — 뒤쪽 줄과 건수가 잘렸다", name, len(rows))
        return rows
