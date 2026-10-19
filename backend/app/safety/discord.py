"""신고 알림(디스코드 신고 전용 채널).

**번호만 싣는다** — 신고 id · 대상 profile_id · 사유 코드 · 누적 신고자 수. 스냅샷 · 메시지 본문 · 닉네임 ·
사진 경로는 절대 싣지 않는다(2026-09-19 결정). 채널에 본문이 흐르면 웹훅 히스토리에 영구히 남는다 —
운영자는 번호를 보고 관리자 웹(ADMIN_BASE_URL 이 있을 때 그 신고의 주소) 또는 Supabase 대시보드에서 본다.
"""
import logging

import httpx

from app.safety.reasons import AUTO_HIDE_REPORTERS

logger = logging.getLogger(__name__)


def _report_url(admin_base_url: str, report_id: str) -> str:
    """관리자 웹(설계 10-18 §8-2 C)의 그 신고 화면. 로그인 · 2단계 뒤에만 열린다. 주소에도 번호만 싣는다."""
    return f"{admin_base_url.rstrip('/')}/reports/{report_id}"


def report_line(report_id: str, target_profile_id: str, reason: str, reporters: int | str, admin_base_url: str = "") -> str:
    """reporters 는 세기가 실패하면 "?" 다(safety/router.py ⑥). 관리자 웹 주소(ADMIN_BASE_URL)가 비면 Supabase 안내다."""
    where = (f"대시보드: {_report_url(admin_base_url, report_id)}" if admin_base_url
             else "Supabase 대시보드에서 확인해 주세요.")
    return (
        f"신고 1건 (신고: {report_id}, 대상: {target_profile_id}, 사유: {reason}, "
        f"누적 신고자: {reporters}명). {where}"
    )


def auto_hidden_line(target_profile_id: str, report_id: str, admin_base_url: str = "") -> str:
    """시각(auto_hidden_at)만 지우면 열린 신고 셋이 그대로라 다음 신고 한 건에 다시 가려진다 — 열린 신고도 닫아야 풀린다.
    대시보드의 가림 해제는 둘을 한 번에 한다(DB 함수 admin_unhide_profile)."""
    what = (f"대시보드에서 정지하거나 가림 해제해 주세요: {_report_url(admin_base_url, report_id)}" if admin_base_url
            else "정지하거나, 풀려면 auto_hidden_at 을 비우고 열린 신고를 dismissed 로 닫아 주세요.")
    return (
        f"신고자 {AUTO_HIDE_REPORTERS}명 도달 · 검토 필요 (대상: {target_profile_id}). "
        f"카드에서 자동으로 가렸어요. {what}"
    )


class ReportNotifier:
    """실패를 삼킨다 — 신고 요청이 디스코드 때문에 실패하면 안 된다. 이미 차단 · 신고는 끝난 뒤다."""

    def __init__(self, webhook_url: str, client: httpx.AsyncClient):
        self._webhook_url = webhook_url
        self._client = client

    async def send(self, content: str) -> None:
        if not self._webhook_url:
            logger.warning("신고 알림 웹훅이 비어 있어 디스코드에 보내지 않았다")
            return
        try:
            response = await self._client.post(self._webhook_url, json={"content": content})
        except Exception:
            logger.exception("신고 디스코드 알림 실패")
            return
        if not response.is_success:
            # raise_for_status 를 쓰지 않는다 — 그 예외 문구에는 웹훅 주소(토큰 포함)가 통째로 들어간다.
            logger.error("신고 디스코드 알림 실패 status=%s", response.status_code)
