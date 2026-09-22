import json
from datetime import datetime

import httpx

from app.chat.repository import ChatRepository
from app.core.time import SEOUL

URL = "https://x.supabase.co/rest/v1"
ME = "11111111-1111-1111-1111-111111111111"
MATCH = "22222222-2222-2222-2222-222222222222"


def _repo(handler) -> ChatRepository:
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return ChatRepository(URL, "service-key", client)


async def test_conversations_hide_closed_rooms_and_rooms_i_left():
    """결정 3·7: 닫힌 방과 내가 나간 방만 뺀다. 상대가 나간 방은 목록에 남아야 한다."""
    seen: list[httpx.QueryParams] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request.url.params)
        return httpx.Response(200, json=[])

    await _repo(handler).fetch_conversations(ME)

    params = seen[0]
    assert params["profile_id"] == f"eq.{ME}"
    assert params["left_at"] == "is.null"
    assert params["matches.chat_closed_at"] == "is.null"
    # 상대 쪽 left_at 은 조건에 들어가면 안 된다 — 들어가면 나간 상대의 방이 목록에서 사라진다.
    assert "matches.match_participants.left_at" not in params


async def test_messages_ask_for_the_newest_fifty_first():
    seen: list[httpx.QueryParams] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request.url.params)
        return httpx.Response(200, json=[])

    await _repo(handler).fetch_messages(MATCH)

    # id 가 두 번째 정렬 열쇠다 — 같은 시각 두 줄의 순서가 흔들리면 페이지 경계에서 줄이 샌다.
    assert seen[0]["order"] == "created_at.desc,id.desc"
    assert seen[0]["limit"] == "50"
    assert "or" not in seen[0]


async def test_older_messages_are_asked_for_with_before():
    seen: list[httpx.QueryParams] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request.url.params)
        return httpx.Response(200, json=[])

    before = datetime(2026, 9, 22, 10, 0, tzinfo=SEOUL)
    await _repo(handler).fetch_messages(MATCH, before=before)

    assert seen[0]["or"] == f"(created_at.lt.{before.isoformat()})"


async def test_the_cursor_keeps_ties_from_being_skipped():
    """같은 트랜잭션에서 들어간 두 줄은 created_at 이 같다. 시각만으로 자르면 하나가 사라진다."""
    seen: list[httpx.QueryParams] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request.url.params)
        return httpx.Response(200, json=[])

    before = datetime(2026, 9, 22, 10, 0, tzinfo=SEOUL)
    await _repo(handler).fetch_messages(MATCH, before=before, before_id="msg-9")

    cursor = before.isoformat()
    assert seen[0]["or"] == f"(created_at.lt.{cursor},and(created_at.eq.{cursor},id.lt.msg-9))"


async def test_unread_count_skips_my_own_messages():
    seen: list[httpx.QueryParams] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request.url.params)
        return httpx.Response(200, json=[{"id": "m1"}, {"id": "m2"}])

    assert await _repo(handler).count_unread(MATCH, ME, "2026-09-22T10:00:00+09:00") == 2
    assert seen[0]["sender_id"] == f"neq.{ME}"
    assert seen[0]["created_at"] == "gt.2026-09-22T10:00:00+09:00"


async def test_unread_count_without_a_read_mark_counts_everything():
    seen: list[httpx.QueryParams] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request.url.params)
        return httpx.Response(200, json=[{"id": "m1"}])

    assert await _repo(handler).count_unread(MATCH, ME, None) == 1
    assert "created_at" not in seen[0]


async def test_system_messages_send_their_kind_explicitly():
    """기본값에 기대면 kind 를 빠뜨린 자리가 조용히 말풍선이 된다."""
    seen: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(json.loads(request.content))
        return httpx.Response(201, json=[{"id": "msg-1"}])

    await _repo(handler).insert_message(MATCH, ME, "가나다님이 채팅방을 나갔어요", kind="left")

    assert seen[0]["kind"] == "left"
    assert seen[0]["match_id"] == MATCH


async def test_leave_is_false_when_it_was_already_left():
    """두 번 나가면 두 번째는 고친 행이 없다 — 시스템 줄을 두 번 넣지 않게 하는 신호다."""
    seen: list[httpx.QueryParams] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request.url.params)
        return httpx.Response(200, json=[])

    assert await _repo(handler).leave(MATCH, ME, datetime.now(SEOUL)) is False
    assert seen[0]["left_at"] == "is.null"


async def test_trust_accept_only_writes_when_nothing_was_answered():
    seen: list[tuple[httpx.QueryParams, dict]] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append((request.url.params, json.loads(request.content)))
        return httpx.Response(200, json=[{"profile_id": ME}])

    assert await _repo(handler).save_trust_accept(MATCH, ME, datetime.now(SEOUL)) is True

    params, body = seen[0]
    assert params["trust_response"] == "is.null"
    # 거절을 쓰는 길은 없다(결정 11) — 이 메서드는 accept 만 쓴다.
    assert body["trust_response"] == "accept"


async def test_pass_trust_gate_is_false_when_someone_already_stamped_it():
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.params["trust_passed_at"] == "is.null"
        return httpx.Response(200, json=[])

    assert await _repo(handler).pass_trust_gate(MATCH, datetime.now(SEOUL)) is False


async def test_close_chat_is_false_when_it_was_already_closed():
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.params["chat_closed_at"] == "is.null"
        return httpx.Response(200, json=[])

    assert await _repo(handler).close_chat(MATCH, datetime.now(SEOUL)) is False


async def test_open_matches_skip_passed_and_closed_ones():
    seen: list[httpx.QueryParams] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request.url.params)
        return httpx.Response(200, json=[])

    await _repo(handler).fetch_open_matches()

    assert seen[0]["trust_passed_at"] == "is.null"
    assert seen[0]["chat_closed_at"] == "is.null"
    # 상한이 없으면 db-max-rows 에 조용히 잘려 마감이 밀린다.
    assert int(seen[0]["limit"]) > 0


async def test_fetch_match_refuses_someone_elses_room():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=[{
            "id": MATCH, "profile_a": "a", "profile_b": "b", "created_at": "2026-09-22T10:00:00+09:00",
            "trust_passed_at": None, "chat_closed_at": None,
            "match_participants": [{"profile_id": "a"}, {"profile_id": "b"}],
        }])

    assert await _repo(handler).fetch_match(MATCH, ME) is None
