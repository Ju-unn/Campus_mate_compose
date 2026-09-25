from uuid import UUID

import httpx

from app.core.http import raise_for_status
from app.student_verification.matching import REVIEW_REASON_LABELS, ReviewReason


class DiscordNotifier:
    def __init__(self, webhook_url: str, client: httpx.AsyncClient):
        self._webhook_url = webhook_url
        self._client = client

    async def notify_pending_review(self, reason: ReviewReason, profile_id: UUID) -> None:
        # 사진·실명·학교명·OCR 원문은 보내지 않는다(설계 §7.3, 2026-09-19 결정).
        # 사유는 어느 쪽이 어긋났는지까지만, 계정은 **id 만** 붙인다(2026-09-26 사용자 결정) —
        # 담당자가 대시보드에서 그 행을 바로 찾을 수 있게 하는 값이고 그 자체로는 사람을 알려주지 않는다.
        content = (
            f"학생증 재검토가 1건 있어요 (사유: {REVIEW_REASON_LABELS[reason]}, 계정: {profile_id}). "
            "Supabase 대시보드에서 확인해 주세요."
        )
        response = await self._client.post(self._webhook_url, json={"content": content})
        raise_for_status(response)

    async def notify_orphaned_file(self, file_path: str) -> None:
        # 인증은 이미 끝났으니 이 알림이 실패해도 요청을 실패시키지 않는다 — 호출부가 결과를 보지 않는다.
        response = await self._client.post(
            self._webhook_url,
            json={"content": f"학생증 사진 삭제가 실패했어요, 고아 파일이 남았어요: `{file_path}`. Storage 에서 손으로 지워 주세요."},
        )
        raise_for_status(response)
