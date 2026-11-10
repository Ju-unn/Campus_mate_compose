"""문의 알림 메일. 문의 저장이 기준이라 메일은 덤이다 — 비밀번호가 없거나 보내다 실패해도 문의는 그대로 저장돼 있다.

표준 smtplib 만 쓴다(새 의존성 없음). 지메일 SSL(465)로 앱 비밀번호 로그인.
로그에는 문의 번호만 남긴다 — 본문 · 메일 주소 · 서버가 돌려준 문장(주소가 섞일 수 있다)은 남기지 않는다.
"""
import asyncio
import logging
import smtplib
import ssl
from datetime import datetime
from email.message import EmailMessage

from app.core.time import SEOUL
from app.inquiries.reasons import REASON_LABELS
from app.settings import Settings

logger = logging.getLogger(__name__)

SMTP_HOST = "smtp.gmail.com"
SMTP_PORT = 465
SMTP_TIMEOUT_SECONDS = 10


def build_message(settings: Settings, *, inquiry_id: str, reason: str, body: str, reply_email: str,
                  account_id: str, received_at: datetime) -> EmailMessage:
    """받는 사람(운영자)이 메일의 '답장'만 눌러도 사용자에게 가도록 Reply-To 를 사용자 메일로 한다."""
    message = EmailMessage()
    message["Subject"] = f"[CampusMate 문의] {REASON_LABELS[reason]} · 문의 번호 {inquiry_id[:8]}"
    message["From"] = settings.inquiry_smtp_user
    message["To"] = settings.inquiry_notify_to
    message["Reply-To"] = reply_email
    message.set_content("\n".join([
        f"사유: {REASON_LABELS[reason]}",
        f"답장 메일: {reply_email}",
        f"문의 번호: {inquiry_id}",
        f"접수 시각: {received_at.astimezone(SEOUL):%Y-%m-%d %H:%M} (한국 시간)",
        f"계정 번호: {account_id}",
        "",
        "내용:",
        body,
    ]))
    return message


def _send(settings: Settings, message: EmailMessage) -> None:
    with smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT, context=ssl.create_default_context(), timeout=SMTP_TIMEOUT_SECONDS) as smtp:
        smtp.login(settings.inquiry_smtp_user, settings.inquiry_smtp_password)
        smtp.send_message(message)


async def notify(settings: Settings, **fields) -> None:
    """저장된 문의 하나를 운영 메일로 알린다. 어떤 실패도 밖으로 던지지 않는다(문의는 이미 저장됐다)."""
    inquiry_id = fields["inquiry_id"]
    if not settings.inquiry_smtp_password:
        logger.warning("문의 메일 건너뜀(비밀번호 없음) inquiry=%s", inquiry_id)
        return
    try:
        # smtplib 는 막는 호출이라 이벤트 루프 밖 스레드에서 돈다.
        await asyncio.to_thread(_send, settings, build_message(settings, **fields))
    except Exception as exc:
        logger.warning("문의 메일 보내기 실패 inquiry=%s %s", inquiry_id, type(exc).__name__)
