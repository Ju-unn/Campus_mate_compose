"""내 글에 댓글이 달리면 글쓴이에게 가는 푸시의 규칙: 본인 댓글 · 스위치 · 10분 묶음 · 문구 · 밤 보관."""
import json
from datetime import datetime, timedelta, timezone

import httpx
import pytest

from app.cards.push import FcmSender, notify, send_pending
from app.cards.repository import NOTIFICATION_DEFAULTS
from app.community import comment_push
from app.community.comment_push import notify_post_author
from app.community.repository import CommunityRepository
from app.core.time import SEOUL

AUTHOR = "99999999-9999-9999-9999-999999999999"
COMMENTER = "11111111-1111-1111-1111-111111111111"
POLL = "22222222-2222-2222-2222-222222222222"
NOW = datetime(2026, 11, 10, 12, 0, tzinfo=timezone.utc)
DAY = datetime(2026, 11, 10, 12, 0, tzinfo=SEOUL)
NIGHT = datetime(2026, 11, 10, 23, 0, tzinfo=SEOUL)
MORNING = datetime(2026, 11, 11, 8, 0, tzinfo=SEOUL)
DATA = {"route": "poll", "poll_id": POLL}


class _Credentials:
    valid = True
    token = "ya29.test"


class _Repo:
    """push.notify 가 쓰는 저장소 자리의 가짜 — test_push_inbox.py 와 같은 모양."""

    def __init__(self, settings=None, status="active"):
        self._settings, self._status = settings or {}, status
        self.pending: list[dict] = []
        self.inbox: list[tuple] = []

    async def insert_notification(self, profile_id, kind, title, body, data):
        self.inbox.append((profile_id, kind, title, body, data))

    async def insert_pending_push(self, profile_id, kind, title, body, data):
        self.pending.append({"id": f"r{len(self.pending)}", "profile_id": profile_id, "kind": kind,
                             "title": title, "body": body, "data": data})

    async def fetch_pending_pushes(self):
        return list(self.pending)

    async def claim_pending_pushes(self, ids):
        claimed = [row for row in self.pending if row["id"] in ids]
        self.pending = [row for row in self.pending if row["id"] not in ids]
        return claimed

    async def fetch_profile_status(self, profile_id):
        return self._status

    async def fetch_push_tokens(self, profile_id):
        return ["tok"]

    async def fetch_notification_settings(self, profile_id):
        return {**NOTIFICATION_DEFAULTS, **self._settings}

    async def delete_push_token(self, token, profile_id):
        pass


def _sender():
    sent: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        sent.append(json.loads(request.content)["message"])
        return httpx.Response(200, json={})

    return FcmSender("campus-mate", httpx.AsyncClient(transport=httpx.MockTransport(handler)),
                     credentials=_Credentials()), sent


def _community(recent: list[dict], seen: list[httpx.Request] | None = None) -> CommunityRepository:
    def handler(request: httpx.Request) -> httpx.Response:
        if seen is not None:
            seen.append(request)
        return httpx.Response(200, json=recent)

    return CommunityRepository("https://x.supabase.co/rest/v1", "service-key",
                               httpx.AsyncClient(transport=httpx.MockTransport(handler)))


@pytest.fixture
def pushes(monkeypatch) -> list[tuple]:
    calls: list[tuple] = []

    async def fake_notify(repo, sender, profile_id, kind, title, body, data, now):
        calls.append((profile_id, kind, title, body, data))
        return 1

    monkeypatch.setattr(comment_push, "notify", fake_notify)
    return calls


async def _go(community, commenter=COMMENTER, question="학식 vs 편의점") -> None:
    await notify_post_author(community, object(), object(), poll_id=POLL, poll_author_id=AUTHOR,
                             question=question, commenter_id=commenter, now=NOW)


# 보낼지 말지 ----------------------------------------------------------------

async def test_pushes_the_poll_author_once_with_title_question_and_poll_data(pushes):
    await _go(_community([]))
    assert pushes == [(AUTHOR, "poll_comment", "내 질문에 새 댓글이 달렸어요", "학식 vs 편의점", DATA)]


async def test_does_not_push_when_the_author_comments_on_their_own_poll(pushes):
    seen: list[httpx.Request] = []
    await _go(_community([], seen), commenter=AUTHOR)
    assert pushes == []
    assert seen == []  # 묶음 확인(DB 읽기)도 하지 않는다


async def test_does_not_push_when_this_poll_already_notified_the_author_in_the_last_10_minutes(pushes):
    await _go(_community([{"id": "n1"}]))
    assert pushes == []


async def test_looks_for_the_same_poll_and_kind_only_since_10_minutes_ago(pushes):
    seen: list[httpx.Request] = []
    await _go(_community([], seen))
    (request,) = seen
    assert request.url.path == "/rest/v1/notifications"
    params = request.url.params
    assert params["profile_id"] == f"eq.{AUTHOR}"
    assert params["kind"] == "eq.poll_comment"
    assert params["data->>poll_id"] == f"eq.{POLL}"
    assert params["created_at"] == f"gte.{(NOW - timedelta(minutes=10)).isoformat()}"
    assert params["limit"] == "1"


@pytest.mark.parametrize(("question", "shown"), [
    ("가" * 20, "가" * 20),
    ("가" * 21, "가" * 20 + "…"),
    ("짧은 질문", "짧은 질문"),
], ids=["20자", "21자", "짧음"])
async def test_body_is_the_first_20_characters_of_the_question(pushes, question, shown):
    await _go(_community([]), question=question)
    assert pushes[0][3] == shown


# 진짜 notify 를 지나면(스위치 · 정지 · 밤) -----------------------------------------

async def test_switch_off_keeps_the_inbox_line_but_sends_no_push():
    """사용자 결정(2026-11-10) 「알림 설정에 끄기 칸」. 스위치는 푸시만 끈다 — 알림함에는 남는다(사용자 결정 2026-10-10)."""
    repo, (sender, sent) = _Repo({"poll_comment": False}), _sender()

    count = await notify(repo, sender, AUTHOR, "poll_comment", "제목", "본문", DATA, now=DAY)

    assert count == 0 and sent == []
    assert repo.inbox == [(AUTHOR, "poll_comment", "제목", "본문", DATA)]


async def test_switch_on_by_default_sends_and_records():
    repo, (sender, sent) = _Repo(), _sender()

    count = await notify(repo, sender, AUTHOR, "poll_comment", "제목", "본문", DATA, now=DAY)

    assert count == 1
    assert sent[0]["data"] == DATA
    assert repo.inbox == [(AUTHOR, "poll_comment", "제목", "본문", DATA)]


@pytest.mark.parametrize("status", ["suspended", "withdrawn"])
async def test_no_push_and_no_inbox_for_an_inactive_author(status):
    repo, (sender, sent) = _Repo(status=status), _sender()

    assert await notify(repo, sender, AUTHOR, "poll_comment", "제목", "본문", DATA, now=DAY) == 0
    assert sent == [] and repo.inbox == []


async def test_at_night_the_push_is_kept_for_the_morning_and_sent_one_by_one():
    repo, (sender, sent) = _Repo({"quiet_hours": True}), _sender()
    other = {"route": "poll", "poll_id": "44444444-4444-4444-4444-444444444444"}
    await notify(repo, sender, AUTHOR, "poll_comment", "제목", "첫 글", DATA, now=NIGHT)
    await notify(repo, sender, AUTHOR, "poll_comment", "제목", "둘째 글", other, now=NIGHT)

    assert sent == [] and len(repo.pending) == 2 and len(repo.inbox) == 2

    assert await send_pending(repo, sender, MORNING) == 2
    assert [(m["notification"]["body"], m["data"]) for m in sent] == [("첫 글", DATA), ("둘째 글", other)]
    assert len(repo.inbox) == 2  # 아침 발송은 알림함에 다시 쓰지 않는다


async def test_a_night_of_comments_on_one_poll_is_one_morning_push_per_poll():
    """밤새 한 글에 댓글이 10분마다 달리면 보관함에 줄이 쌓인다 — 아침에는 같은 사람 · 같은 글이 한 건으로 나간다(문구는 그대로)."""
    repo, (sender, sent) = _Repo({"quiet_hours": True}), _sender()
    other = {"route": "poll", "poll_id": "44444444-4444-4444-4444-444444444444"}
    for _ in range(3):
        await notify(repo, sender, AUTHOR, "poll_comment", "내 질문에 새 댓글이 달렸어요", "학식 vs 편의점", DATA, now=NIGHT)
    await notify(repo, sender, AUTHOR, "poll_comment", "내 질문에 새 댓글이 달렸어요", "다른 질문", other, now=NIGHT)
    assert len(repo.pending) == 4 and sent == []

    assert await send_pending(repo, sender, MORNING) == 2

    assert [(m["notification"]["title"], m["notification"]["body"], m["data"]) for m in sent] == [
        ("내 질문에 새 댓글이 달렸어요", "학식 vs 편의점", DATA),
        ("내 질문에 새 댓글이 달렸어요", "다른 질문", other),
    ]
    assert repo.pending == []  # 합쳐서 버린 줄도 보관함에서 지워진다


async def test_the_morning_dedupe_is_per_person():
    repo, (sender, sent) = _Repo({"quiet_hours": True}), _sender()
    for person in (AUTHOR, COMMENTER):
        await notify(repo, sender, person, "poll_comment", "제목", "본문", DATA, now=NIGHT)

    assert await send_pending(repo, sender, MORNING) == 2


def test_the_switch_exists_with_default_on():
    assert NOTIFICATION_DEFAULTS["poll_comment"] is True
