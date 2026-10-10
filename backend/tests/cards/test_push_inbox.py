"""푸시가 지나가는 notify() 가 알림함(notifications 표)에도 한 줄 남기는지 본다(설계 §7·§8-4)."""
import json
import logging
from datetime import datetime

import httpx
import pytest

from app.cards.push import FcmSender, notify, send_pending
from app.cards.repository import CardRepository
from app.core.time import SEOUL

DAY = datetime(2026, 10, 10, 12, 0, tzinfo=SEOUL)
NIGHT = datetime(2026, 10, 10, 23, 0, tzinfo=SEOUL)
MORNING = datetime(2026, 10, 11, 8, 0, tzinfo=SEOUL)
DATA = {"route": "acceptances"}


class _Credentials:
    valid = True
    token = "ya29.test"


class _Repo:
    def __init__(self, settings=None, status="active", pending=None, insert_error=None):
        self._settings, self._status = settings or {}, status
        self.pending = list(pending or [])
        self.pending_deleted: list[str] = []
        self.inbox: list[tuple] = []
        self._insert_error = insert_error

    async def insert_notification(self, profile_id, kind, title, body, data):
        if self._insert_error:
            raise self._insert_error
        self.inbox.append((profile_id, kind, title, body, data))

    async def insert_pending_push(self, profile_id, kind, title, body, data):
        self.pending.append({"id": f"r{len(self.pending)}", "profile_id": profile_id, "kind": kind,
                             "title": title, "body": body, "data": data})

    async def fetch_pending_pushes(self):
        return list(self.pending)

    async def delete_pending_pushes(self, ids):
        self.pending_deleted.extend(ids)

    async def fetch_profile_status(self, profile_id):
        return self._status

    async def fetch_push_tokens(self, profile_id):
        return ["tok"]

    async def fetch_notification_settings(self, profile_id):
        return dict(self._settings)

    async def delete_push_token(self, token, profile_id):
        pass


def _sender():
    pushes: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        pushes.append(json.loads(request.content)["message"])
        return httpx.Response(200, json={})

    sender = FcmSender("campus-mate", httpx.AsyncClient(transport=httpx.MockTransport(handler)),
                       credentials=_Credentials())
    return sender, pushes


@pytest.mark.parametrize("push_kind, inbox_kind", [
    ("card_arrived", "card_arrived"),
    ("acceptance_received", "chat_request"),
    ("match_made", "match_made"),
    ("new_friend_review", "friend_review"),
    ("verification_result", "verification_result"),
])
async def test_a_push_kind_is_recorded_under_its_inbox_kind(push_kind, inbox_kind):
    repo, (sender, pushes) = _Repo(), _sender()

    await notify(repo, sender, "p1", push_kind, "제목", "본문", DATA, now=DAY)

    # data 는 푸시 data 그대로 — 눌렀을 때 가는 화면(route)이 같아야 한다.
    assert repo.inbox == [("p1", inbox_kind, "제목", "본문", DATA)]
    assert len(pushes) == 1


@pytest.mark.parametrize("push_kind", ["new_message", "trust_reminder"])
async def test_chat_and_gate_pushes_are_not_recorded(push_kind):
    repo, (sender, pushes) = _Repo(), _sender()

    await notify(repo, sender, "p1", push_kind, "제목", "본문", DATA, now=DAY)

    assert repo.inbox == []
    assert len(pushes) == 1


async def test_a_switched_off_kind_is_still_recorded_but_not_pushed():
    """사용자 결정(2026-10-10): 스위치는 푸시만 끈다. 알림함(종)에는 남아서 다시 볼 수 있다."""
    repo, (sender, pushes) = _Repo({"acceptance_received": False}), _sender()

    sent = await notify(repo, sender, "p1", "acceptance_received", "제목", "본문", DATA, now=DAY)

    assert repo.inbox == [("p1", "chat_request", "제목", "본문", DATA)]  # 한 번만
    assert sent == 0 and pushes == []


async def test_a_switched_off_kind_at_night_is_recorded_once_and_not_kept_for_the_morning():
    repo, (sender, pushes) = _Repo({"acceptance_received": False}), _sender()

    await notify(repo, sender, "p1", "acceptance_received", "제목", "본문", DATA, now=NIGHT)

    assert len(repo.inbox) == 1 and repo.pending == [] and pushes == []


async def test_a_switch_turned_off_overnight_does_not_record_again_in_the_morning():
    repo, (sender, pushes) = _Repo(), _sender()
    await notify(repo, sender, "p1", "acceptance_received", "제목", "본문", DATA, now=NIGHT)
    repo._settings = {"acceptance_received": False}  # 밤사이 스위치를 껐다

    assert await send_pending(repo, sender, MORNING) == 0

    assert pushes == [] and len(repo.inbox) == 1  # 푸시는 안 가고, 기록은 밤의 한 줄 그대로
    assert repo.pending_deleted == ["r0"]


@pytest.mark.parametrize("status", ["suspended", "withdrawn"])
async def test_a_suspended_or_withdrawn_recipient_gets_no_record(status):
    repo, (sender, _) = _Repo(status=status), _sender()

    await notify(repo, sender, "p1", "match_made", "제목", "본문", DATA, now=DAY)

    assert repo.inbox == []


async def test_a_night_push_is_recorded_at_once_even_though_the_push_waits():
    repo, (sender, pushes) = _Repo(), _sender()

    await notify(repo, sender, "p1", "acceptance_received", "제목", "본문", DATA, now=NIGHT)

    assert [row[1] for row in repo.inbox] == ["chat_request"]
    assert len(repo.pending) == 1 and pushes == []


async def test_a_night_push_that_is_dropped_instead_of_kept_is_still_recorded():
    """defer=False(방금 화면에서 본 일)는 푸시를 버리지만 알림함은 기록이다 — 낮에는 둘 다 남는 것과 같다."""
    repo, (sender, pushes) = _Repo(), _sender()

    await notify(repo, sender, "p1", "match_made", "제목", "본문", DATA, now=NIGHT, defer=False)

    assert len(repo.inbox) == 1 and repo.pending == [] and pushes == []


async def test_the_morning_resend_does_not_record_again():
    repo, (sender, pushes) = _Repo(), _sender()
    await notify(repo, sender, "p1", "acceptance_received", "제목", "본문", DATA, now=NIGHT)

    assert await send_pending(repo, sender, MORNING) == 1

    assert len(pushes) == 1
    assert len(repo.inbox) == 1  # 밤에 남긴 한 줄이 전부다


async def test_a_morning_bundle_does_not_add_a_record_either():
    repo, (sender, pushes) = _Repo(), _sender()
    for _ in range(3):
        await notify(repo, sender, "p1", "acceptance_received", "제목", "본문", DATA, now=NIGHT)

    await send_pending(repo, sender, MORNING)

    assert len(pushes) == 1  # 3건이 한 묶음 푸시로
    assert len(repo.inbox) == 3  # 알림함에는 밤에 온 3줄 그대로


async def test_a_failing_record_does_not_stop_the_push():
    repo, (sender, pushes) = _Repo(insert_error=RuntimeError("db down")), _sender()

    sent = await notify(repo, sender, "p1", "card_arrived", "제목", "본문", DATA, now=DAY)

    assert sent == 1 and len(pushes) == 1


async def test_a_failing_record_does_not_stop_the_night_keeping():
    repo, (sender, _) = _Repo(insert_error=RuntimeError("db down")), _sender()

    await notify(repo, sender, "p1", "acceptance_received", "제목", "본문", DATA, now=NIGHT)

    assert len(repo.pending) == 1


async def test_a_failing_record_logs_the_profile_but_never_the_words(caplog):
    repo, (sender, _) = _Repo(insert_error=RuntimeError("db down")), _sender()

    with caplog.at_level(logging.ERROR):
        await notify(repo, sender, "profile-123", "card_arrived", "닉네임님이 신청했어요", "비밀 본문", DATA, now=DAY)

    assert "profile-123" in caplog.text
    assert "닉네임님이 신청했어요" not in caplog.text and "비밀 본문" not in caplog.text


async def test_the_repository_writes_one_row_to_notifications():
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(201)

    repo = CardRepository("https://x.supabase.co/rest/v1", "service-key",
                          httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    await repo.insert_notification("p1", "chat_request", "제목", "본문", {"route": "acceptances"})

    (request,) = seen
    assert (request.method, request.url.path) == ("POST", "/rest/v1/notifications")
    assert json.loads(request.content) == {"profile_id": "p1", "kind": "chat_request", "title": "제목",
                                           "body": "본문", "data": {"route": "acceptances"}}
