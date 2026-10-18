"""관리자 운영 상태판(설계 10-18 §8-4 E, 화면 A2). 읽기만 한다 — DB 함수 admin_health 가 개수만 돌려주고, 정상 / 경고 / 위험 판단은 여기 상수가 한다.

기준값을 바꿀 때는 이 파일 위쪽 상수만 고친다(마이그레이션 없음). 값은 대장 확정(10-18):
  ① 카드: 지급 요일 + 지급 시각 + 60분 뒤에, 받을 사람이 있는 지역 중 한 곳도 오늘 카드를 못 받았으면 위험(일부 지역만 0장은 정상) / ② 안 닫힌 방: 48시간 + 배치 여유 2시간 = 50시간 /
  ③ 탈퇴 31일 / ④ 아바타 실패 최근 24시간 / ⑤ 보류 푸시 12시간(정상 최대 10시간 + 2).
환불 배치는 DB 흔적이 없어 여기서 볼 수 없다 — 응답의 unobservable 로 알린다.
"""
from datetime import datetime

from fastapi import APIRouter, Depends

from app.admin.caller import AdminCaller, get_admin_caller
from app.admin.stats_repository import AdminStatsRepository
from app.core.deps import get_now

router = APIRouter()

CARDS_GRACE_MINUTES = 60
ROOM_HOURS = 50
WITHDRAWN_DAYS = 31
AVATAR_HOURS = 24
PUSH_HOURS = 12

# 화면 순서 그대로. (응답 키, DB 칸, 경고 최소 개수, 위험 최소 개수) — 카드(①)는 개수 기준이 없어 따로 판정한다.
COUNTED = (
    ("stuck_chat_rooms", "stuck_rooms", 1, 5),
    ("overdue_withdrawn", "overdue_withdrawn", 1, 100),
    ("avatar_failures_24h", "avatar_failures", 1, 3),
    ("stuck_pending_pushes", "stuck_pushes", 1, 20),
)
# 서버가 볼 수 없는 점검. 환불 배치는 DB 에 흔적이 없다(로그에서 확인).
UNOBSERVABLE = ["refund_batch"]


def status_for(count: int, warn: int, alert: int) -> str:
    return "alert" if count >= alert else "warn" if count >= warn else "ok"


def _cards(row: dict) -> dict:
    # 목적은 "지급 배치가 아예 안 돌았는지" 다. 점검 대상(오늘이 지급 요일이고 시각 + 여유가 지났고, 카드를 받은 사람이 있거나 받을 사람이 있는
    # 지역)이 없으면 — 지급 요일 아님 · 지급 시각 전 · 받을 사람 없음(11/2 전 코호트) — "정상" 이 아니라 "해당 없음"이다.
    # 점검 대상 지역 어딘가에 오늘 카드가 한 장이라도 나갔으면 정상(후보 부족으로 일부 지역만 0장인 것은 경고하지 않는다),
    # 한 지역도 못 받았으면 위험(count = 점검 대상 지역 수).
    checked, issued = row["cards_checked"], row["cards_issued"]
    if checked == 0:
        return {"key": "cards_issued_today", "status": "na", "count": 0}
    if issued >= 1:
        return {"key": "cards_issued_today", "status": "ok", "count": 0}
    return {"key": "cards_issued_today", "status": "alert", "count": checked}


@router.get("/health")
async def get_health(caller: AdminCaller = Depends(get_admin_caller), now: datetime = Depends(get_now)) -> dict:
    row = await AdminStatsRepository(
        caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client,
    ).health(cards_grace_minutes=CARDS_GRACE_MINUTES, room_hours=ROOM_HOURS, withdrawn_days=WITHDRAWN_DAYS,
             avatar_hours=AVATAR_HOURS, push_hours=PUSH_HOURS)
    return {
        "checked_at": now.isoformat(),
        "items": [_cards(row), *({"key": key, "status": status_for(row[field], warn, alert), "count": row[field]}
                                 for key, field, warn, alert in COUNTED)],
        "unobservable": UNOBSERVABLE,
    }
