"""신고 알림(디스코드 신고 전용 채널).

**번호만 싣는다** — 신고 id · 대상 profile_id · 사유 코드 · 누적 신고자 수. 스냅샷 · 메시지 본문 · 닉네임 ·
사진 경로는 절대 싣지 않는다(2026-09-19 결정). 채널에 본문이 흐르면 웹훅 히스토리에 영구히 남는다 —
운영자는 번호를 보고 Supabase 대시보드에서 본다.
"""
import logging

import httpx

from app.safety.reasons import AUTO_HIDE_REPORTERS

logger = logging.getLogger(__name__)


def report_line(report_id: str, target_profile_id: str, reason: str, reporters: int | str) -> str:
    """reporters 는 세기가 실패하면 "?" 다(safety/router.py ⑥)."""
    return (
        f"신고 1건 (신고: {report_id}, 대상: {target_profile_id}, 사유: {reason}, "
        f"누적 신고자: {reporters}명). Supabase 대시보드에서 확인해 주세요."
    )


def auto_hidden_line(target_profile_id: str) -> str:
    return (
        f"신고자 {AUTO_HIDE_REPORTERS}명 도달 · 검토 필요 (대상: {target_profile_id}). "
        "카드에서 자동으로 가렸어요. 정지하거나 auto_hidden_at 을 지워 주세요."
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
