"""문의하기. 사유 + 내용 + 답장 받을 메일을 저장하고 운영 메일로 알린다(메일 실패는 로그만, 응답은 201).

로그인만 확인한다(get_caller) — 정지된 사람 · 학교 메일/학과 입력 전인 가입 중 사람도 보낼 수 있어야 한다.
탈퇴한 계정만 401 이다. 관리자 쪽은 admin/inquiry_review.py.
"""
import asyncio
import logging
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, field_validator

from app.core import errors
from app.core.deps import Caller, get_caller, get_now
from app.inquiries import mailer
from app.inquiries.reasons import BODY_MAX, DAILY_INQUIRY_LIMIT, EMAIL_MAX, REPLY_EMAIL, Reason
from app.inquiries.repository import InquiryRepository
from app.settings import Settings

logger = logging.getLogger(__name__)
router = APIRouter()

# 메일을 기다리는 최대 시간. smtplib 의 접속 제한(10초)은 접속 뒤 단계를 못 막아 응답이 오래 걸릴 수 있다.
MAIL_WAIT_SECONDS = 15
# 그 안에서 쓴 사람 닉네임 읽기를 기다리는 최대 시간. 늦으면 '알 수 없음' 으로 보내 메일 보낼 시간을 남긴다.
AUTHOR_WAIT_SECONDS = 3


class InquiryRequest(BaseModel):
    reason: Reason
    body: str
    reply_email: str

    @field_validator("body")
    @classmethod
    def _body_length(cls, value: str) -> str:
        value = value.strip()
        if not 1 <= len(value) <= BODY_MAX:
            raise ValueError(f"내용은 1~{BODY_MAX}자여야 한다")
        if "\x00" in value:  # Postgres text 는 NUL 을 못 담는다 — 저장에서 500 이 나기 전에 거절
            raise ValueError("내용에 쓸 수 없는 문자가 있다")
        return value

    @field_validator("reply_email")
    @classmethod
    def _email_shape(cls, value: str) -> str:
        value = value.strip()
        # 줄바꿈 · 공백이 낀 값은 정규식이 막는다 — 메일 헤더(Reply-To) 주입 방지.
        if len(value) > EMAIL_MAX or not REPLY_EMAIL.fullmatch(value):
            raise ValueError("답장 받을 메일 형식이 맞지 않는다")
        return value


@router.post("/inquiries", status_code=201)
async def create_inquiry(
    body: InquiryRequest, caller: Caller = Depends(get_caller), now: datetime = Depends(get_now),
) -> dict:
    settings, client, account_id = caller
    repo = InquiryRepository(settings.postgrest_url, settings.supabase_service_role_key, client)

    # 하루 상한(한국 시간 0시부터). 막힌 시도는 저장도 메일도 하지 않는다.
    today = now.replace(hour=0, minute=0, second=0, microsecond=0)
    # shortcut: 세고 넣는 사이가 한 트랜잭션이 아니라 동시에 보내면 한두 건 넘을 수 있다 — 신고 상한(safety)과 같은 방식. 막을 일이 생기면 DB 함수로.
    if await repo.count_since(account_id, today, DAILY_INQUIRY_LIMIT) >= DAILY_INQUIRY_LIMIT:
        raise HTTPException(status_code=429, detail=errors.INQUIRY_DAILY_LIMIT)

    inquiry_id = await repo.insert(account_id, body.reason, body.body, body.reply_email)
    try:
        # 닉네임 읽기까지 합쳐 MAIL_WAIT_SECONDS 하나 안에서 끝낸다.
        await asyncio.wait_for(_notify(settings, repo, inquiry_id, body, str(account_id), now), MAIL_WAIT_SECONDS)
    except TimeoutError as exc:
        # 메일은 덤이다 — 문의는 이미 저장됐으니 오래 기다리지 않고 201 을 준다. 로그는 문의 번호 + 예외 이름만.
        logger.warning("문의 메일 보내기 실패 inquiry=%s %s", inquiry_id, type(exc).__name__)
    return {"ok": True, "id": inquiry_id}


async def _notify(settings: Settings, repo: InquiryRepository, inquiry_id: str, body: InquiryRequest, account_id: str,
                  now: datetime) -> None:
    """쓴 사람의 닉네임 · 학교를 한 번 읽어 메일에 싣는다. 읽기가 실패하거나 늦으면 '알 수 없음' 으로 그대로 보낸다."""
    try:
        nickname, school = await asyncio.wait_for(repo.fetch_author(account_id), AUTHOR_WAIT_SECONDS)
    except Exception as exc:
        logger.warning("문의 작성자 읽기 실패 inquiry=%s %s", inquiry_id, type(exc).__name__)
        nickname = school = None
    await mailer.notify(settings, inquiry_id=inquiry_id, reason=body.reason, body=body.body,
                        reply_email=body.reply_email, account_id=account_id, received_at=now,
                        nickname=nickname, school=school)
