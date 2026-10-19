import logging
from uuid import UUID

import httpx

from app.student_verification.matching import REVIEW_REASON_LABELS, ReviewReason

_logger = logging.getLogger(__name__)


class DiscordNotifier:
    """학생증 재검토 채널 알림. **실패를 삼킨다** — 알림이 실패해도 부른 요청(학생증 제출 · 서버 시작)은 그대로 간다.
    상태는 이미 DB 에 적혔고 운영자는 대시보드로도 본다(safety/discord.py · heart_tasks/router.py 와 같은 규칙)."""

    def __init__(self, webhook_url: str, client: httpx.AsyncClient):
        self._webhook_url = webhook_url
        self._client = client

    async def notify_pending_review(self, reason: ReviewReason, profile_id: UUID) -> None:
        # 사진·실명·학교명·OCR 원문은 보내지 않는다(설계 §7.3, 2026-09-19 결정).
        # 사유는 어느 쪽이 어긋났는지까지만, 계정은 **id 만** 붙인다(2026-09-26 사용자 결정) —
        # 담당자가 대시보드에서 그 행을 바로 찾을 수 있게 하는 값이고 그 자체로는 사람을 알려주지 않는다.
        await self._send(
            f"학생증 재검토가 1건 있어요 (사유: {REVIEW_REASON_LABELS[reason]}, 계정: {profile_id}). "
            "Supabase 대시보드에서 확인해 주세요."
        )

    async def notify_graduate_request(self, request_id: UUID, profile_id: UUID) -> None:
        # 사진 · 번호 · 이메일 · 학교 글자는 보내지 않는다(COMMON §3) — 신청 id 와 계정 id 만. 관리자 웹에서 그 신청을 연다.
        await self._send(
            f"졸업생 인증 신청이 1건 들어왔어요 (신청: {request_id}, 계정: {profile_id}). 관리자 웹에서 확인해 주세요."
        )

    async def notify_graduate_orphaned_file(self, profile_id: UUID) -> None:
        # 신청 줄을 못 쓰고 방금 올린 사진도 못 지웠다. 사진 경로는 싣지 않는다(COMMON §3) — 계정 id 가 곧 폴더 이름이다.
        await self._send(
            f"졸업생 인증 사진 삭제가 실패해 고아 파일이 남았어요 (계정: {profile_id}). "
            "Storage graduate-cert-temp 에서 그 계정 폴더를 손으로 지워 주세요."
        )

    async def notify_orphaned_file(self, profile_id: UUID) -> None:
        # 사진 경로는 싣지 않는다(COMMON §3) — 계정 id 가 곧 Storage 폴더 이름이다.
        await self._send(
            f"학생증 사진 삭제가 실패해 고아 파일이 남았어요 (계정: {profile_id}). "
            "Storage student-id-temp 에서 그 계정 폴더를 손으로 지워 주세요."
        )

    async def notify_missing_fallback_avatar(self, source_path: str) -> None:
        # 서버 시작 때 한 번 — 인스턴스가 여러 개 뜨면 같은 알림이 여러 번 갈 수 있다(막지 않는다).
        # 사람 사진이 아니라 고정된 기본 그림 경로라 그대로 싣는다.
        await self._send(
            f"기본 아바타 원본이 없어요: `avatars/{source_path}`. 5번째 아바타 실패 보상이 멈춰요. "
            "DEPLOY.md §4-2 대로 업로드해 주세요."
        )

    async def _send(self, content: str) -> None:
        # raise_for_status 를 쓰지 않는다 — 그 예외 문구에는 웹훅 주소(토큰 포함)가 통째로 들어가 로그에 남는다
        # (2026-10-12 보안 점검 #9). 상태 코드 · 예외 이름만 남긴다.
        # InvalidURL(설정 오류 모양의 주소)은 HTTPError 하위가 아니라 따로 잡는다.
        try:
            response = await self._client.post(self._webhook_url, json={"content": content})
        except (httpx.HTTPError, httpx.InvalidURL) as exc:
            _logger.warning("디스코드 알림 실패 %s", type(exc).__name__)
            return
        if not response.is_success:
            _logger.warning("디스코드 알림 실패 status=%s", response.status_code)
