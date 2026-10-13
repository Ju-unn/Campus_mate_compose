"""채팅 실시간 전환 안 A(10-13 설계안): 서버가 쓰기 직후 `user:<profile_id>` 비공개 채널로 Broadcast 를 쏜다.

쏘기는 덤이다 — 실패해도 메시지 · 읽음 · 닫기는 그대로 성공해야 하고, 방을 나간(left_at) 사람에게는 가지 않는다."""
import json
import logging
from datetime import datetime

import httpx

from app.chat.realtime import Broadcaster
from app.chat.repository import ChatRepository
from app.core.time import SEOUL

SUPABASE = "https://x.supabase.co"
ME = "11111111-1111-1111-1111-111111111111"
PARTNER = "22222222-2222-2222-2222-222222222222"
MATCH = "33333333-3333-3333-3333-333333333333"
NOW = datetime(2026, 10, 13, 14, 0, tzinfo=SEOUL)
BROADCAST_PATH = "/realtime/v1/api/broadcast"


def _broadcaster(handler, url: str = SUPABASE, key: str = "service-key") -> Broadcaster:
    return Broadcaster(url, key, httpx.AsyncClient(transport=httpx.MockTransport(handler)))


# Broadcaster ---------------------------------------------------------------------

async def test_one_call_carries_every_recipient_on_their_own_private_channel():
    seen: list[httpx.Request] = []

    def handler(request):
        seen.append(request)
        return httpx.Response(202)

    await _broadcaster(handler).send([ME, PARTNER], "message", {"match_id": MATCH})

    assert len(seen) == 1
    request = seen[0]
    assert request.method == "POST"
    assert str(request.url) == f"{SUPABASE}{BROADCAST_PATH}"
    # PostgREST 와 같은 서비스 키 두 헤더 — 로컬 스파이크에서 이 조합으로 private 채널에 닿았다.
    assert request.headers["apikey"] == "service-key"
    assert request.headers["authorization"] == "Bearer service-key"
    assert json.loads(request.content) == {"messages": [
        {"topic": f"user:{ME}", "event": "message", "payload": {"match_id": MATCH}, "private": True},
        {"topic": f"user:{PARTNER}", "event": "message", "payload": {"match_id": MATCH}, "private": True},
    ]}


async def test_the_call_gives_up_after_about_a_second_and_a_half():
    seen: list[httpx.Request] = []

    def handler(request):
        seen.append(request)
        return httpx.Response(202)

    await _broadcaster(handler).send([ME], "read", {})

    assert seen[0].extensions["timeout"] == {"connect": 1.5, "read": 1.5, "write": 1.5, "pool": 1.5}


async def test_nobody_to_tell_means_no_call():
    seen: list[httpx.Request] = []
    await _broadcaster(lambda r: seen.append(r) or httpx.Response(202)).send([], "message", {})
    assert seen == []


async def test_without_a_url_or_key_nothing_is_sent():
    seen: list[httpx.Request] = []

    def handler(request):
        seen.append(request)
        return httpx.Response(202)

    await _broadcaster(handler, url="").send([ME], "message", {})
    await _broadcaster(handler, key="").send([ME], "message", {})

    assert seen == []


async def test_a_rejected_call_is_logged_and_swallowed(caplog):
    with caplog.at_level(logging.WARNING, logger="app.chat.realtime"):
        await _broadcaster(lambda r: httpx.Response(500, text="boom service-key")).send([ME], "message", {})

    assert "status=500" in caplog.text
    assert "event=message" in caplog.text
    # 키 · 주소(프로젝트 ref) · 받는 사람 id 는 로그에 남기지 않는다.
    assert "service-key" not in caplog.text
    assert "x.supabase.co" not in caplog.text
    assert ME not in caplog.text


async def test_a_timeout_is_logged_and_swallowed(caplog):
    def handler(request):
        raise httpx.ReadTimeout("slow", request=request)

    with caplog.at_level(logging.WARNING, logger="app.chat.realtime"):
        await _broadcaster(handler).send([ME], "read", {})

    assert "ReadTimeout" in caplog.text
    assert "x.supabase.co" not in caplog.text


async def test_a_batch_broadcaster_stops_trying_after_the_first_failure():
    """배치는 마감 방마다 쏜다 — Realtime 이 죽었으면 방마다 제한시간을 기다려 배치가 길어진다(검토 권고 1)."""
    seen: list[httpx.Request] = []

    def handler(request):
        seen.append(request)
        raise httpx.ConnectTimeout("down", request=request)

    broadcaster = Broadcaster(SUPABASE, "service-key", httpx.AsyncClient(transport=httpx.MockTransport(handler)),
                              give_up_after_failure=True)
    await broadcaster.send([ME], "room_changed", {})
    await broadcaster.send([PARTNER], "room_changed", {})

    assert len(seen) == 1


async def test_an_ordinary_broadcaster_tries_every_time():
    seen: list[httpx.Request] = []

    def handler(request):
        seen.append(request)
        return httpx.Response(500)

    broadcaster = _broadcaster(handler)
    await broadcaster.send([ME], "message", {})
    await broadcaster.send([ME], "message", {})

    assert len(seen) == 2


# 저장소 길목: 메시지 · 읽음 · 닫기 ----------------------------------------------------

class _World:
    """참가자 두 행과 쏘기 기록. 받는 사람 조회는 left_at=is.null 조건을 실제로 따른다."""

    def __init__(self, partner_left: bool = False, members_status: int = 200, broadcast_status: int = 202):
        self.participants = {ME: {"profile_id": ME, "left_at": None},
                             PARTNER: {"profile_id": PARTNER, "left_at": "2026-10-13T13:00:00+09:00" if partner_left else None}}
        self.members_status = members_status
        self.broadcast_status = broadcast_status
        self.sent: list[dict] = []
        self.member_queries: list[httpx.QueryParams] = []

    def handle(self, request: httpx.Request) -> httpx.Response:
        params = request.url.params
        if request.url.path == BROADCAST_PATH:
            self.sent.extend(json.loads(request.content)["messages"])
            return httpx.Response(self.broadcast_status)
        if request.url.path == "/rest/v1/match_participants":
            if request.method == "PATCH":
                row = self.participants[params["profile_id"].removeprefix("eq.")]
                if params.get("left_at") == "is.null" and row["left_at"]:
                    return httpx.Response(200, json=[])
                row.update(json.loads(request.content))
                return httpx.Response(200, json=[row])
            self.member_queries.append(params)
            if self.members_status != 200:
                return httpx.Response(self.members_status)
            rows = [p for p in self.participants.values()
                    if params.get("left_at") != "is.null" or p["left_at"] is None]
            return httpx.Response(200, json=[{"profile_id": p["profile_id"]} for p in rows])
        if request.url.path == "/rest/v1/messages":
            body = json.loads(request.content)
            # PostgREST return=representation 은 행 전체를 준다 — 이벤트에는 고른 칸만 실어야 한다.
            return httpx.Response(201, json=[{"id": "msg-1", **body, "created_at": "2026-10-13T14:00:00+09:00"}])
        if request.url.path == "/rest/v1/matches":
            return httpx.Response(200, json=[{"id": MATCH}])
        if request.url.path == "/rest/v1/profiles":
            return httpx.Response(200, json=[{"nickname": "나나"}])
        return httpx.Response(200, json=[])

    def repo(self, broadcast: bool = True) -> ChatRepository:
        client = httpx.AsyncClient(transport=httpx.MockTransport(self.handle))
        return ChatRepository(f"{SUPABASE}/rest/v1", "service-key", client,
                              broadcaster=Broadcaster(SUPABASE, "service-key", client) if broadcast else None)

    def to(self, event: str) -> list[str]:
        return [m["topic"] for m in self.sent if m["event"] == event]


async def test_a_new_message_goes_to_both_people_with_only_the_list_fields():
    world = _World()

    await world.repo().insert_message(MATCH, ME, "안녕")

    # 보낸 사람도 받는다 — 같은 사람의 다른 기기 목록이 맞춰진다.
    assert world.to("message") == [f"user:{ME}", f"user:{PARTNER}"]
    assert world.sent[0]["payload"] == {"match_id": MATCH, "message": {
        "id": "msg-1", "sender_id": ME, "kind": "text", "body": "안녕",
        "created_at": "2026-10-13T14:00:00+09:00",
    }}
    assert world.member_queries[0]["left_at"] == "is.null"


async def test_a_message_skips_someone_who_left():
    world = _World(partner_left=True)

    await world.repo().insert_message(MATCH, ME, "안녕")

    assert world.to("message") == [f"user:{ME}"]


async def test_leaving_tells_only_the_one_who_stays():
    """나가기(차단도 같은 함수)는 left_at 을 먼저 찍는다 — 그래서 시스템 줄 이벤트에서 나간 사람이 빠진다."""
    world = _World()

    assert await world.repo().leave_and_announce(MATCH, ME, NOW)

    assert world.to("message") == [f"user:{PARTNER}"]
    message = world.sent[0]["payload"]["message"]
    assert (message["kind"], message["body"]) == ("left", "나나님이 채팅방을 나갔어요")


async def test_reading_tells_only_the_partner_when_i_read():
    world = _World()

    await world.repo().touch_read(MATCH, ME, NOW)

    assert world.to("read") == [f"user:{PARTNER}"]
    assert world.sent[0]["payload"] == {"match_id": MATCH, "reader_id": ME, "last_read_at": NOW.isoformat()}


async def test_reading_tells_nobody_when_the_partner_left():
    world = _World(partner_left=True)

    await world.repo().touch_read(MATCH, ME, NOW)

    assert world.sent == []


async def test_closing_tells_both_once():
    world = _World()
    repo = world.repo()

    assert await repo.close_chat(MATCH, NOW)

    assert world.to("room_changed") == [f"user:{ME}", f"user:{PARTNER}"]
    assert world.sent[0]["payload"] == {"match_id": MATCH, "reason": "closed"}


async def test_an_already_closed_room_tells_nobody():
    world = _World()

    def handle(request):
        if request.url.path == "/rest/v1/matches":
            return httpx.Response(200, json=[])  # 조건부 PATCH 가 고친 행 없음 = 이미 닫힘
        return world.handle(request)

    client = httpx.AsyncClient(transport=httpx.MockTransport(handle))
    repo = ChatRepository(f"{SUPABASE}/rest/v1", "k", client, broadcaster=Broadcaster(SUPABASE, "k", client))

    assert not await repo.close_chat(MATCH, NOW)
    assert world.sent == []


async def test_a_failing_recipient_lookup_does_not_undo_the_message(caplog):
    world = _World(members_status=500)

    with caplog.at_level(logging.WARNING, logger="app.chat.repository"):
        row = await world.repo().insert_message(MATCH, ME, "안녕")

    assert row["id"] == "msg-1"
    assert world.sent == []
    assert "event=message" in caplog.text


async def test_a_failing_broadcast_does_not_undo_the_read():
    world = _World(broadcast_status=503)

    await world.repo().touch_read(MATCH, ME, NOW)

    assert world.participants[ME]["last_read_at"] == NOW.isoformat()


async def test_without_a_broadcaster_the_repository_makes_no_extra_calls():
    """배치 · 계정 · 지인 리뷰처럼 쏠 일이 없는 저장소는 받는 사람 조회도 하지 않는다."""
    world = _World()

    await world.repo(broadcast=False).insert_message(MATCH, ME, "안녕")

    assert world.member_queries == []
    assert world.sent == []
