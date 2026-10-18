"""인증샷 승인 · 반려 결과를 사용자에게 알린다(사용자 결정 10-18 "가"). 문구는 pen `푸시_문구_표.png` 그대로다.

푸시와 알림함 한 줄은 기존 push.notify() 가 한다(알림함은 즉시, 조용한 시간엔 푸시만 아침 보관함, 정지 · 탈퇴는 건너뜀).
알림 실패 · 시간 초과는 승인 · 반려 결과를 되돌리지 않는다 — DB 에서는 이미 끝났고, 로그만 남긴다.
data 에는 route · task · reason 만 싣는다(사진 경로 · 관리자 · 메모 금지).
"""
import asyncio
import logging
from datetime import datetime
from typing import NamedTuple

from app.admin.caller import AdminCaller
from app.cards.push import FcmSender, notify
from app.cards.repository import CardRepository

logger = logging.getLogger(__name__)

# 관리자 버튼 응답이 FCM 때문에 오래 막히지 않게 하는 상한(대장 결정 10-18). 넘으면 거기서 그만두고 200 은 그대로 준다.
NOTICE_TIMEOUT_SECONDS = 5.0

TASK_TITLE = {"everytime_post": "에브리타임 홍보", "kakao_share": "단톡방 공유"}
# 앱 frontend/lib/billing/model/heart_task.dart HeartTaskRejectReason.label 과 글자까지 같다(enum public.heart_task_reject_reason).
REASON_TEXT = {
    "date_missing": "날짜가 안 보여요",
    "not_verified": "게시글·공유가 확인되지 않아요",
    "reused": "이미 쓴 캡처예요",
}


class ResultNotice(NamedTuple):
    kind: str
    title: str
    body: str
    data: dict[str, str]


def result_notice(task: str, status: str, reward_hearts: int, reject_reason: str | None) -> ResultNotice:
    """승인이면 하트 수(서버 값)를, 반려면 사유를 본문에 둔다. 사유가 비었거나 모르는 값이면(DB 가 막아 정상에선 없다)
    "다시 제출해 주세요"만 말하고 data 에 reason 을 빼서, 앱이 사유 알림 없는 18b 로 보내게 한다."""
    name = TASK_TITLE[task]
    if status == "approved":
        return ResultNotice("heart_task_approved", f"{name} 인증이 승인됐어요", f"하트 {reward_hearts}개를 받았어요",
                            {"route": "heart_tasks", "task": task})
    reason = REASON_TEXT.get(reject_reason or "")
    data = {"route": "heart_task_retry", "task": task}
    if reason is None:
        return ResultNotice("heart_task_rejected", f"{name} 인증이 반려됐어요", "다시 제출해 주세요", data)
    return ResultNotice("heart_task_rejected", f"{name} 인증이 반려됐어요", f"{reason} · 다시 제출해 주세요",
                        {**data, "reason": reject_reason})


async def send_result_notice(caller: AdminCaller, sender: FcmSender, now: datetime,
                             profile_id: str, notice: ResultNotice) -> None:
    """모든 예외 · 시간 초과를 삼킨다. 로그에는 profile_id 와 kind 만(제목 · 본문 · 사진 경로 금지)."""
    repo = CardRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)
    try:
        await asyncio.wait_for(
            notify(repo, sender, profile_id, notice.kind, notice.title, notice.body, notice.data, now),
            timeout=NOTICE_TIMEOUT_SECONDS)
    except asyncio.TimeoutError:
        logger.warning("인증샷 결과 알림 시간 초과 profile=%s kind=%s", profile_id, notice.kind)
    except Exception:
        logger.exception("인증샷 결과 알림 실패 profile=%s kind=%s", profile_id, notice.kind)
