import asyncio
import logging
from datetime import datetime

import google.auth
import httpx
from google.auth.transport.requests import Request as GoogleAuthRequest

logger = logging.getLogger(__name__)

_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
# 조용한 시간(설계 화면 16d): 22시 ~ 다음날 8시.
_QUIET_START_HOUR = 22
_QUIET_END_HOUR = 8
# 카드 도착 알림은 지급 시각(07:00)이 조용한 시간 안이라 예외다 — 아니면 영영 못 간다.
# 채팅도 예외다(2026-09-22 사용자 결정, 조각 5 결정 5) — 대화는 밤에도 오간다.
# 게이트 알림(trust_reminder · match_made)은 예외가 아니다. 대신 리마인드는 보낼 시각 자체를
# 아침 8시로 밀어 두기 때문에 조용한 시간에 버려지지 않는다(chat/gate.py 의 reminder_at).
_QUIET_HOURS_EXEMPT = {"card_arrived", "new_message"}
# 조용한 시간에 걸리면 버리지 않고 pending_pushes 에 넣어 아침에 묶어 보낸다(결정 4, 2026-10-01 사용자).
# 학생증 검토 결과(A7)도 예외가 아니라 보관함으로 간다 — 예외는 채팅 · 카드 도착뿐이다(사용자 규칙).
_DEFERRED = {"acceptance_received", "match_made", "new_friend_review", "verification_result"}
# 알림함(설계 §7·§8-4)에 남기는 푸시 kind -> notifications.kind. 여기 없는 kind(채팅 new_message ·
# 게이트 trust_reminder)는 알림함에 쌓지 않는다.
_INBOX_KINDS = {
    "card_arrived": "card_arrived",
    "acceptance_received": "chat_request",
    "match_made": "match_made",
    "new_friend_review": "friend_review",
    "verification_result": "verification_result",
}
# 아침 묶음 문구. 사람 × (kind, 가는 화면 data.route)로 묶는다 — 같은 kind 라도 가는 화면이 달라서다.
# 여기 없는 짝(친구 가입 → 리뷰 쓰기, 학생증 검토 결과)은 알림마다 내용 · 갈 곳이 달라 묶지 않고 한 건씩 보낸다.
_BUNDLES = {
    # 받는 쪽 버튼이 "대화 신청하기" · 목록이 "받은 신청" 이다(지시문 22 G). kind 와 설정 키는 그대로 둔다.
    ("acceptance_received", "acceptances"): ("대화 신청이 왔어요", "밤사이 {n}명이 대화를 신청했어요"),
    ("match_made", "match"): ("매칭됐어요!", "밤사이 {n}명과 매칭됐어요"),
    # 방 id 없이 보내면 앱이 방 대신 대화 목록을 연다(push_route.dart).
    ("match_made", "chat"): ("카카오톡 아이디를 주고받았어요", "밤사이 {n}명과 프로필이 공개됐어요"),
    ("new_friend_review", "friend_reviews"): ("새 지인 리뷰가 도착했어요", "밤사이 리뷰 {n}개가 도착했어요"),
}


class FcmSender:
    """FCM HTTP v1 에 알림 한 건을 보낸다. 자격증명은 Cloud Run 서비스 계정(ADC)이다 —
    Vision 과 같은 방식이고 서버 키를 따로 만들지 않는다(2026-09-20 준비 가이드)."""

    def __init__(self, project_id: str, client: httpx.AsyncClient, credentials=None):
        self._project_id = project_id
        self._client = client
        self._credentials = credentials

    async def _access_token(self) -> str:
        if self._credentials is None:
            self._credentials, _ = await asyncio.to_thread(google.auth.default, scopes=[_SCOPE])
        if not self._credentials.valid:
            # refresh 는 requests 로 동기 호출이라 이벤트 루프를 막지 않게 스레드로 돌린다.
            await asyncio.to_thread(self._credentials.refresh, GoogleAuthRequest())
        return self._credentials.token

    async def send(self, token: str, title: str, body: str, data: dict[str, str]) -> str:
        """`"sent"` · `"dead"` · `"failed"` 중 하나. `"dead"` 일 때만 부른 쪽이 토큰을 지운다.

        400 은 죽은 토큰이 아니라 우리가 보낸 payload 가 잘못됐다는 뜻이다 — 예전에는 404 와
        한데 묶여서 멀쩡한 사람의 토큰을 조용히 지웠다."""
        payload = {
            "message": {
                "token": token,
                "notification": {"title": title, "body": body},
                # data 값은 문자열만 허용된다. 앱은 route 로 어느 화면을 열지 고른다(Task A7).
                "data": {key: str(value) for key, value in data.items()},
                "android": {"priority": "high"},
            }
        }
        response = await self._client.post(
            f"https://fcm.googleapis.com/v1/projects/{self._project_id}/messages:send",
            json=payload,
            headers={"Authorization": f"Bearer {await self._access_token()}"},
        )
        if response.status_code == 404:
            return "dead"
        if not response.is_success:
            # 푸시 실패가 카드 지급을 되돌리게 두지 않는다 — 로그만 남기고 넘어간다.
            logger.warning("FCM 전송 실패 %s %s", response.status_code, response.text[:200])
            return "failed"
        return "sent"


def _is_quiet(now: datetime) -> bool:
    return now.hour >= _QUIET_START_HOUR or now.hour < _QUIET_END_HOUR


async def _record(repo, profile_id, kind: str, title: str, body: str, data: dict[str, str]) -> None:
    """알림함에 한 줄 남긴다. 실패는 로그만 — 푸시 · 카드 지급 · 결정 저장을 막지 않는다.
    로그에는 title · body 를 남기지 않는다(닉네임이 들어갈 수 있다). profile_id 와 kind 만."""
    inbox_kind = _INBOX_KINDS.get(kind)
    if inbox_kind is None:
        return
    try:
        await repo.insert_notification(profile_id, inbox_kind, title, body, data)
    except Exception:
        logger.exception("알림함 기록 실패 profile=%s kind=%s", profile_id, kind)


async def notify(repo, sender: FcmSender, profile_id, kind: str,
                 title: str, body: str, data: dict[str, str], now: datetime, defer: bool = True,
                 record: bool = True) -> int:
    """알림 스위치와 조용한 시간을 본 뒤 그 사람의 모든 기기로 보낸다. 보낸 건수를 돌려준다.
    푸시와 같은 관문(정지 · 탈퇴 · 스위치)을 지난 알림은 조용한 시간이어도 그 순간 알림함에 한 줄 남는다.

    `defer=False` 면 조용한 시간에 보류하지 않고 옛날처럼 버린다 — 방금 화면에서 본 일을 알리는 자리용이다.
    `record=False` 는 알림함에 이미 남긴 알림을 다시 보내는 자리(아침 묶음)용이다 — 중복 기록을 막는다."""
    if await repo.fetch_profile_status(profile_id) in ("suspended", "withdrawn"):
        # 조각 6: 정지 · 탈퇴 계정에는 어떤 알림도 보내지 않는다. 모든 푸시가 이 함수를 지나서 한 곳만 본다.
        # 탈퇴는 토큰도 지우지만 best-effort 라 남을 수 있어 여기서 한 번 더 막는다.
        return 0
    settings = await repo.fetch_notification_settings(profile_id)
    if not settings.get(kind, True):
        return 0
    if record:
        await _record(repo, profile_id, kind, title, body, data)
    if settings.get("quiet_hours", True) and kind not in _QUIET_HOURS_EXEMPT and _is_quiet(now):
        if defer and kind in _DEFERRED:
            await repo.insert_pending_push(profile_id, kind, title, body, data)
        return 0

    sent = 0
    for token in await repo.fetch_push_tokens(profile_id):
        result = await sender.send(token, title, body, data)
        if result == "sent":
            sent += 1
        elif result == "dead":
            # 이 토큰은 방금 profile_id 로 꺼내 온 것이라 주인이 확실하다.
            await repo.delete_push_token(token, profile_id)
    return sent


async def send_pending(repo, sender: FcmSender, now: datetime) -> int:
    """매시 chat-gate 배치가 부른다. 조용하지 않은 시각이면 밤에 보류한 알림을 사람 × kind × 가는 화면으로 묶어
    보내고 지운다 — 보통 08시에 비고, 08시 배치가 실패하면 다음 시각이 보낸다. 실제로 간 알림 수를 돌려준다."""
    if _is_quiet(now):
        return 0
    groups: dict[tuple, list[dict]] = {}
    for row in await repo.fetch_pending_pushes():
        groups.setdefault((row["profile_id"], row["kind"], row["data"].get("route")), []).append(row)

    sent = 0
    for (profile_id, kind, route), rows in groups.items():
        if len(rows) > 1 and (kind, route) in _BUNDLES:
            title, body = _BUNDLES[(kind, route)]
            # 묶음은 목록 화면으로 간다 — 어느 한 건의 card_id · match_id 를 달지 않는다.
            pushes = [(kind, title, body.format(n=len(rows)), {"route": route})]
        else:
            pushes = [(row["kind"], row["title"], row["body"], row["data"]) for row in rows]
        for kind, title, body, data in pushes:
            try:
                # notify 를 다시 지난다 — 밤사이 끈 알림 · 정지 · 탈퇴는 여기서 걸린다.
                # 알림함에는 밤에 이미 남겼으므로 record=False 로 중복 기록을 막는다.
                sent += 1 if await notify(repo, sender, profile_id, kind, title, body, data, now=now, record=False) else 0
            except Exception:
                # 한 사람 알림 때문에 뒷사람 묶음까지 멈추는 쪽이 훨씬 나쁘다.
                logger.exception("아침 묶음 알림 실패 profile=%s route=%s", profile_id, route)
        # 실패해도 지운다 — 남기면 매시 같은 실패를 되풀이하거나 점심에 "밤사이" 알림이 간다.
        await repo.delete_pending_pushes([row["id"] for row in rows])
    return sent
