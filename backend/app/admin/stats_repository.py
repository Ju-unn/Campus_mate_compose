"""관리자 홈 통계 · 그래프 · 미등록 도메인 · 학교별 현황 · 운영 상태판(설계 10-18 §8-4 · §8-4b)의 DB 호출. 전부 읽기 전용 DB 함수다
(마이그레이션 20261018150000, service_role 만 execute). 날짜 묶음 · 조건부 개수는 PostgREST 로 못 한다."""
from app.admin.repository import AdminRepository


class AdminStatsRepository(AdminRepository):

    async def overview(self) -> dict:
        """상태별 인원 · 열린 신고 · 검수 대기 · 오늘 / 7일 가입(관리자 제외) 한 줄."""
        return (await self._rpc("admin_stats_overview", {}))[0]

    async def daily(self, days: int) -> list[dict]:
        """한국 시간 하루 단위 [{day, male_signups, female_signups, report_count, proof_count}] 오래된 순, 정확히 days 줄."""
        return await self._rpc("admin_stats_daily", {"p_days": days})

    async def unknown_domains(self, limit: int) -> list[dict]:
        """시도 많은 순 [{domain, attempt_count, first_seen_at, last_seen_at}]. 이미 등록된 도메인은 DB 함수가 뺀다."""
        return await self._rpc("admin_unknown_domains", {"p_limit": limit})

    async def universities(self, include_empty: bool) -> list[dict]:
        """학교별 카드 오픈 시각 · 남녀 활성 인원. include_empty 가 false 면 활성 0 이고 오픈 시각도 없는 학교는 뺀다."""
        return await self._rpc("admin_universities_status", {"p_include_empty": include_empty})

    async def health(self, *, cards_grace_minutes: int, room_hours: int, withdrawn_days: int, avatar_hours: int, push_hours: int) -> dict:
        """운영 상태판 개수 한 줄(DB 함수 admin_health). 판단 기준(창)은 부르는 쪽이 넘긴다."""
        return (await self._rpc("admin_health", {
            "p_cards_grace_minutes": cards_grace_minutes, "p_room_hours": room_hours, "p_withdrawn_days": withdrawn_days,
            "p_avatar_hours": avatar_hours, "p_push_hours": push_hours,
        }))[0]
