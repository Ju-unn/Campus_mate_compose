import json
from collections.abc import Callable
from datetime import datetime

import httpx
import pytest
from fastapi.testclient import TestClient

import app.chat.router as router_module
from app.cards.push import FcmSender
from app.core.deps import get_client, get_now, get_settings
from app.core.time import SEOUL
from app.main import app
from app.settings import Settings

PROFILE_ID = "11111111-1111-1111-1111-111111111111"
PARTNER_ID = "22222222-2222-2222-2222-222222222222"
MATCH_ID = "33333333-3333-3333-3333-333333333333"
AUTH_HEADERS = {"Authorization": "Bearer valid-token"}
# 시각은 의존성으로 끼운다. 벽시계를 그대로 쓰면 조용한 시간(22~08시)에 푸시가 버려져
# 밤에 도는 CI 만 빨개진다 — 낮 하나, 밤 하나를 정해 두고 둘 다 본다.
NOW = datetime(2026, 9, 22, 14, 0, tzinfo=SEOUL)
NIGHT = datetime(2026, 9, 22, 23, 0, tzinfo=SEOUL)

PARTNER_PROFILE = {
    "id": PARTNER_ID, "nickname": "여우비",
    "profile_avatars": [{"storage_path": "p2/a.png", "status": "ready",
                         "created_at": "2026-09-20T00:00:00+00:00"}],
}


class _FakeCredentials:
    valid = True
    token = "ya29.test"


@pytest.fixture(autouse=True)
def overrides():
    app.dependency_overrides[get_settings] = lambda: Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test",
    )
    # 푸시 건수를 세는 테스트가 quiet_hours 를 켜는 파일이라면 거기서도 get_now 를 같이 끼워야 한다.
    # conftest 에 전역으로 두지는 말 것 — test_acceptances 의 _hours_ago 처럼 벽시계를 쓰는 곳이 깨진다.
    app.dependency_overrides[get_now] = lambda: NOW
    yield
    app.dependency_overrides.clear()


def _wire(handler: Callable[[httpx.Request], httpx.Response]) -> TestClient:
    def wrapped(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/auth/v1/user" in url:
            return httpx.Response(200, json={"id": PROFILE_ID})
        if "student_verification" in url and request.method == "GET":
            return httpx.Response(200, json=[{"student_verification": "verified", "department": "컴공"}])
        return handler(request)

    client = httpx.AsyncClient(transport=httpx.MockTransport(wrapped))
    app.dependency_overrides[get_client] = lambda: client
    app.dependency_overrides[router_module.get_sender] = lambda: FcmSender(
        "campus-mate-test", client, credentials=_FakeCredentials()
    )
    return TestClient(app)


def _match(**overrides) -> dict:
    """살아 있는 방 하나. 매칭 시각은 기한이 넉넉히 남도록 먼 미래로 둔다."""
    participants = overrides.pop("participants", None) or [
        {"profile_id": PROFILE_ID, "trust_response": None, "left_at": None, "last_read_at": None},
        {"profile_id": PARTNER_ID, "trust_response": None, "left_at": None, "last_read_at": None},
    ]
    return {
        "id": MATCH_ID, "profile_a": PROFILE_ID, "profile_b": PARTNER_ID,
        "created_at": "2126-09-22T10:00:00+09:00",
        "trust_passed_at": None, "chat_closed_at": None,
        "match_participants": participants, **overrides,
    }


class _Calls:
    """목 트랜스포트가 받은 요청을 갈래별로 모아 둔다."""

    def __init__(self) -> None:
        self.messages: list[dict] = []
        self.pushes: list[dict] = []
        self.patches: list[tuple[str, dict]] = []


def _handler(calls: _Calls, match: dict, *, messages: list[dict] | None = None,
             patch_rows: list[dict] | None = None):
    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "fcm.googleapis.com" in url:
            calls.pushes.append(json.loads(request.content)["message"])
            return httpx.Response(200, json={"name": "projects/x/messages/1"})
        if "/rest/v1/matches" in url:
            if request.method == "PATCH":
                calls.patches.append((url, json.loads(request.content)))
                return httpx.Response(200, json=patch_rows if patch_rows is not None else [match])
            return httpx.Response(200, json=[match])
        if "/rest/v1/match_participants" in url:
            if request.method == "PATCH":
                calls.patches.append((url, json.loads(request.content)))
                return httpx.Response(200, json=patch_rows if patch_rows is not None else [{"x": 1}])
            return httpx.Response(200, json=[])
        if "/rest/v1/messages" in url:
            if request.method == "POST":
                calls.messages.append(json.loads(request.content))
                return httpx.Response(201, json=[{"id": "msg-1", **json.loads(request.content)}])
            return httpx.Response(200, json=messages or [])
        if "/rest/v1/profiles" in url:
            return httpx.Response(200, json=[PARTNER_PROFILE if "nickname" not in url else PARTNER_PROFILE])
        if "/rest/v1/notification_settings" in url:
            return httpx.Response(200, json=[])
        if "/rest/v1/push_tokens" in url:
            return httpx.Response(200, json=[{"token": "tok"}])
        return httpx.Response(200, json=[])

    return handler


# 방 조회 ---------------------------------------------------------------------

def test_someone_elses_room_is_not_found():
    stranger = _match(participants=[
        {"profile_id": "other-a", "trust_response": None, "left_at": None, "last_read_at": None},
        {"profile_id": "other-b", "trust_response": None, "left_at": None, "last_read_at": None},
    ])
    response = _wire(_handler(_Calls(), stranger)).get(
        f"/chat/matches/{MATCH_ID}", headers=AUTH_HEADERS
    )
    assert response.status_code == 404


def test_room_before_the_gate_has_no_kakao_id_or_photos():
    response = _wire(_handler(_Calls(), _match())).get(
        f"/chat/matches/{MATCH_ID}", headers=AUTH_HEADERS
    )

    assert response.status_code == 200
    body = response.json()
    assert body["partner"]["nickname"] == "여우비"
    assert body["partner"]["avatar_url"].endswith("/avatars/p2/a.png")
    assert body["gate"]["passed"] is False
    assert body["gate"]["passed_at"] is None
    # 통과 전에는 키 자체가 없어야 한다 — null 로라도 내려가면 앱이 자리를 그린다.
    assert "kakao_id" not in body
    assert "photo_urls" not in body


def test_room_always_carries_my_own_kakao_id():
    """14f 시트가 "이 아이디를 공유합니다" 로 보여준다 — 게이트 전에도 내 것은 내려간다."""
    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/rest/v1/matches" in url:
            return httpx.Response(200, json=[_match()])
        if "/rest/v1/profile_private" in url:
            # 내 행만 돌려준다 — 상대 아이디는 통과 전에 조회조차 하지 않는다.
            assert f"eq.{PROFILE_ID}" in url
            return httpx.Response(200, json=[{"kakao_id": "my_id"}])
        if "/rest/v1/profiles" in url:
            return httpx.Response(200, json=[PARTNER_PROFILE])
        return httpx.Response(200, json=[])

    body = _wire(handler).get(f"/chat/matches/{MATCH_ID}", headers=AUTH_HEADERS).json()

    assert body["my_kakao_id"] == "my_id"
    assert "kakao_id" not in body


def test_room_after_the_gate_carries_the_kakao_id_and_signed_photos():
    passed = _match(trust_passed_at="2126-09-22T12:00:00+09:00")

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/rest/v1/matches" in url:
            return httpx.Response(200, json=[passed])
        if "/rest/v1/profile_private" in url:
            # 내 행과 상대 행을 갈라 준다 — 두 아이디가 뒤바뀌면 아래 단언이 잡는다.
            if f"eq.{PROFILE_ID}" in url:
                return httpx.Response(200, json=[{"kakao_id": "my_id"}])
            assert f"eq.{PARTNER_ID}" in url
            return httpx.Response(200, json=[{"kakao_id": "fox_rain"}])
        if "/rest/v1/profile_photos" in url:
            return httpx.Response(200, json=[{"storage_path": "p2/1.jpg", "position": 0}])
        if "/storage/v1/object/sign/profile-photos/" in url:
            return httpx.Response(200, json={"signedURL": "/object/sign/profile-photos/p2/1.jpg?token=t"})
        if "/rest/v1/profiles" in url:
            return httpx.Response(200, json=[PARTNER_PROFILE])
        return httpx.Response(200, json=[])

    body = _wire(handler).get(f"/chat/matches/{MATCH_ID}", headers=AUTH_HEADERS).json()

    assert body["kakao_id"] == "fox_rain"
    assert body["my_kakao_id"] == "my_id"
    # 통과 카드를 대화 중 통과 시각 자리에 놓으려고 앱이 쓴다(백로그 20). 원문 그대로 내려간다.
    assert body["gate"]["passed_at"] == "2126-09-22T12:00:00+09:00"
    assert body["photo_urls"] == [
        "https://x.supabase.co/storage/v1/object/sign/profile-photos/p2/1.jpg?token=t"
    ]


def test_a_zero_page_is_refused():
    """0 을 그대로 넘기면 빈 페이지가 돌아와 앱이 "더 없음" 으로 읽는다(#77 리뷰 권고 4번)."""
    response = _wire(_handler(_Calls(), _match())).get(
        f"/chat/matches/{MATCH_ID}/messages?limit=0", headers=AUTH_HEADERS
    )
    assert response.status_code == 422


# 보내기 ----------------------------------------------------------------------

def test_sending_stores_the_message_and_pushes_once():
    calls = _Calls()
    response = _wire(_handler(calls, _match())).post(
        f"/chat/matches/{MATCH_ID}/messages", json={"body": "안녕하세요"}, headers=AUTH_HEADERS
    )

    assert response.status_code == 201
    assert calls.messages[0]["body"] == "안녕하세요"
    assert calls.messages[0]["kind"] == "text"
    assert len(calls.pushes) == 1
    assert calls.pushes[0]["data"]["route"] == "chat"
    assert calls.pushes[0]["notification"]["body"] == "안녕하세요"


def test_no_push_when_the_partner_is_looking_at_the_room():
    """결정 5: 방을 보고 있으면 보내지 않는다. 방금 읽음이 찍힌 것으로 판정한다."""
    looking = _match(participants=[
        {"profile_id": PROFILE_ID, "trust_response": None, "left_at": None, "last_read_at": None},
        {"profile_id": PARTNER_ID, "trust_response": None, "left_at": None,
         "last_read_at": NOW.isoformat()},
    ])
    calls = _Calls()
    _wire(_handler(calls, looking)).post(
        f"/chat/matches/{MATCH_ID}/messages", json={"body": "보고 있어요?"}, headers=AUTH_HEADERS
    )

    assert calls.pushes == []


def test_sending_to_a_closed_room_is_rejected():
    closed = _match(chat_closed_at="2126-09-24T10:00:00+09:00")
    response = _wire(_handler(_Calls(), closed)).post(
        f"/chat/matches/{MATCH_ID}/messages", json={"body": "늦었나요"}, headers=AUTH_HEADERS
    )
    assert response.status_code == 409
    assert response.json()["detail"] == "종료된 대화예요"


def test_sending_after_i_left_is_rejected():
    left = _match(participants=[
        {"profile_id": PROFILE_ID, "trust_response": None, "left_at": "2126-09-22T11:00:00+09:00",
         "last_read_at": None},
        {"profile_id": PARTNER_ID, "trust_response": None, "left_at": None, "last_read_at": None},
    ])
    response = _wire(_handler(_Calls(), left)).post(
        f"/chat/matches/{MATCH_ID}/messages", json={"body": "다시 올게요"}, headers=AUTH_HEADERS
    )
    assert response.status_code == 409
    assert response.json()["detail"] == "이미 나간 대화예요"


def test_sending_after_the_partner_left_is_rejected():
    """결정 7: 상대가 나가면 입력창이 잠긴다. 예전 계획(201 + 푸시 0건)에서 바뀐 자리다."""
    gone = _match(participants=[
        {"profile_id": PROFILE_ID, "trust_response": None, "left_at": None, "last_read_at": None},
        {"profile_id": PARTNER_ID, "trust_response": None, "left_at": "2126-09-22T11:00:00+09:00",
         "last_read_at": None},
    ])
    calls = _Calls()
    response = _wire(_handler(calls, gone)).post(
        f"/chat/matches/{MATCH_ID}/messages", json={"body": "거기 있어요?"}, headers=AUTH_HEADERS
    )

    assert response.status_code == 409
    assert response.json()["detail"] == "상대가 대화를 나갔어요"
    assert calls.messages == []


def test_too_long_and_blank_messages_are_refused():
    client = _wire(_handler(_Calls(), _match()))

    assert client.post(f"/chat/matches/{MATCH_ID}/messages",
                       json={"body": "가" * 1001}, headers=AUTH_HEADERS).status_code == 422
    assert client.post(f"/chat/matches/{MATCH_ID}/messages",
                       json={"body": "   "}, headers=AUTH_HEADERS).status_code == 422


# 나가기 ----------------------------------------------------------------------

def test_leaving_writes_the_system_line_the_partner_will_see():
    calls = _Calls()
    response = _wire(_handler(calls, _match())).post(
        f"/chat/matches/{MATCH_ID}/leave", headers=AUTH_HEADERS
    )

    assert response.status_code == 200
    assert calls.messages[0]["kind"] == "left"
    assert calls.messages[0]["body"] == "여우비님이 채팅방을 나갔어요"
    # 나갔다는 소식으로 알림을 울리지는 않는다.
    assert calls.pushes == []


def test_leaving_twice_does_not_write_a_second_system_line():
    calls = _Calls()
    response = _wire(_handler(calls, _match(), patch_rows=[])).post(
        f"/chat/matches/{MATCH_ID}/leave", headers=AUTH_HEADERS
    )

    assert response.status_code == 409
    assert calls.messages == []


# 신뢰 확인 게이트 --------------------------------------------------------------

def test_accepting_early_is_allowed_and_tells_the_partner():
    """결정 10: 24시간을 기다리지 않는다. 수락은 시스템 줄로 상대에게 보인다."""
    calls = _Calls()
    response = _wire(_handler(calls, _match())).post(
        f"/chat/matches/{MATCH_ID}/trust", headers=AUTH_HEADERS
    )

    assert response.status_code == 200
    assert response.json() == {"passed": False}
    assert calls.messages[0]["kind"] == "trust_accept"
    assert calls.messages[0]["body"] == "여우비님이 카카오톡 아이디·실사진 공개를 수락했어요"
    assert len(calls.pushes) == 1


def _accept_the_gate() -> tuple[dict, _Calls]:
    """상대가 이미 수락한 방에서 내가 수락한다 — 그 자리에서 통과하는 길. 낮·밤 두 테스트가 같이 쓴다."""
    both = _match(participants=[
        {"profile_id": PROFILE_ID, "trust_response": None, "left_at": None, "last_read_at": None},
        {"profile_id": PARTNER_ID, "trust_response": "accept", "left_at": None, "last_read_at": None},
    ])
    calls = _Calls()

    def handler(request: httpx.Request) -> httpx.Response:
        if "/rest/v1/profile_private" in str(request.url):
            return httpx.Response(200, json=[{"kakao_id": "fox_rain"}])
        return _handler(calls, both)(request)

    body = _wire(handler).post(f"/chat/matches/{MATCH_ID}/trust", headers=AUTH_HEADERS).json()
    return body, calls


def test_both_accepting_opens_the_gate_right_away():
    body, calls = _accept_the_gate()

    assert body["passed"] is True
    assert body["kakao_id"] == "fox_rain"
    stamped = [patch for url, patch in calls.patches if "trust_passed_at" in patch]
    assert len(stamped) == 1
    # 수락 알림 1건 + 통과 알림 2건(양쪽)
    assert len(calls.pushes) == 3


def test_the_gate_opens_at_night_too_and_only_the_pass_alarm_waits():
    """조용한 시간에도 문은 열린다. 채팅 푸시만 예외라(결정 5) 통과 알림 2건은 버려진다.

    벽시계를 읽던 시절에는 22시 넘어 돌린 CI 가 이 차이 때문에 빨개졌다."""
    app.dependency_overrides[get_now] = lambda: NIGHT

    body, calls = _accept_the_gate()

    assert body["passed"] is True
    assert body["kakao_id"] == "fox_rain"
    # 문이 열린 도장은 밤에도 똑같이 한 번 찍힌다 — 버려지는 건 푸시뿐이다.
    stamped = [patch for url, patch in calls.patches if "trust_passed_at" in patch]
    assert len(stamped) == 1
    # 남는 건 수락 알림 하나뿐이다 — 채팅 갈래라 조용한 시간을 지나간다.
    assert len(calls.pushes) == 1
    assert calls.pushes[0]["notification"]["body"] == "카카오톡 아이디·실사진 공개를 수락했어요"


def test_the_gate_is_stamped_before_the_system_line():
    """통과 도장이 수락 바로 다음에 찍혀야 한다(#77 리뷰 필수 1번).

    시스템 줄 INSERT 가 터져도 trust_passed_at 은 이미 찍혀 있다. 순서가 반대면 그 자리에서
    끊겼을 때 trust_response=accept 인데 도장이 없는 방이 남고, 다시 눌러도 409 라 되살릴 수 없다."""
    both = _match(participants=[
        {"profile_id": PROFILE_ID, "trust_response": None, "left_at": None, "last_read_at": None},
        {"profile_id": PARTNER_ID, "trust_response": "accept", "left_at": None, "last_read_at": None},
    ])
    calls = _Calls()
    order: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/rest/v1/matches" in url and request.method == "PATCH":
            order.append("stamp")
            calls.patches.append((url, json.loads(request.content)))
            return httpx.Response(200, json=[both])
        if "/rest/v1/messages" in url and request.method == "POST":
            order.append("system_line")
            return httpx.Response(500, json={"message": "서버가 끊겼다"})
        return _handler(calls, both)(request)

    with pytest.raises(httpx.HTTPStatusError):
        _wire(handler).post(f"/chat/matches/{MATCH_ID}/trust", headers=AUTH_HEADERS)

    assert order == ["stamp", "system_line"]
    assert [patch for _, patch in calls.patches if "trust_passed_at" in patch]


def test_a_simultaneous_second_accept_does_not_push_the_reveal_twice():
    both = _match(participants=[
        {"profile_id": PROFILE_ID, "trust_response": None, "left_at": None, "last_read_at": None},
        {"profile_id": PARTNER_ID, "trust_response": "accept", "left_at": None, "last_read_at": None},
    ])
    calls = _Calls()

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/rest/v1/matches" in url and request.method == "PATCH":
            calls.patches.append((url, json.loads(request.content)))
            return httpx.Response(200, json=[])  # 상대가 먼저 찍었다
        return _handler(calls, both)(request)

    body = _wire(handler).post(f"/chat/matches/{MATCH_ID}/trust", headers=AUTH_HEADERS).json()

    assert body == {"passed": True}
    # 내 수락을 알리는 1건만 나간다 — 공개 알림은 먼저 찍은 쪽이 보냈다.
    assert len(calls.pushes) == 1


def test_accepting_twice_is_refused_and_writes_one_system_line():
    calls = _Calls()
    response = _wire(_handler(calls, _match(), patch_rows=[])).post(
        f"/chat/matches/{MATCH_ID}/trust", headers=AUTH_HEADERS
    )

    assert response.status_code == 409
    assert response.json()["detail"] == "이미 수락했어요"
    assert calls.messages == []


def test_accepting_after_the_deadline_is_refused():
    late = _match(created_at="2020-09-22T10:00:00+09:00")
    response = _wire(_handler(_Calls(), late)).post(
        f"/chat/matches/{MATCH_ID}/trust", headers=AUTH_HEADERS
    )

    assert response.status_code == 409
    assert response.json()["detail"] == "응답 기한이 지났어요"


def test_accepting_when_the_partner_left_is_refused():
    gone = _match(participants=[
        {"profile_id": PROFILE_ID, "trust_response": None, "left_at": None, "last_read_at": None},
        {"profile_id": PARTNER_ID, "trust_response": None, "left_at": "2126-09-22T11:00:00+09:00",
         "last_read_at": None},
    ])
    response = _wire(_handler(_Calls(), gone)).post(
        f"/chat/matches/{MATCH_ID}/trust", headers=AUTH_HEADERS
    )

    assert response.status_code == 409
    assert response.json()["detail"] == "상대가 대화를 나갔어요"


# 목록 · 읽음 ------------------------------------------------------------------

def test_conversation_list_shows_the_last_line_and_unread_count():
    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/rest/v1/match_participants" in url:
            return httpx.Response(200, json=[{
                "match_id": MATCH_ID, "last_read_at": None, "trust_response": None,
                "matches": {"id": MATCH_ID, "profile_a": PROFILE_ID, "profile_b": PARTNER_ID,
                            "created_at": "2126-09-22T10:00:00+09:00",
                            "trust_passed_at": None, "chat_closed_at": None},
            }])
        if "/rest/v1/messages" in url:
            return httpx.Response(200, json=[
                {"id": "m2", "sender_id": PARTNER_ID, "kind": "text", "body": "반가워요",
                 "created_at": "2126-09-22T11:00:00+09:00"},
            ])
        if "/rest/v1/profiles" in url:
            return httpx.Response(200, json=[PARTNER_PROFILE])
        return httpx.Response(200, json=[])

    body = _wire(handler).get("/chat/conversations", headers=AUTH_HEADERS).json()

    row = body["conversations"][0]
    assert row["partner"]["nickname"] == "여우비"
    assert row["last_message"] == "반가워요"
    assert row["unread_count"] == 1
    assert row["trust_passed"] is False


def test_read_mark_patches_my_participant_row():
    calls = _Calls()
    response = _wire(_handler(calls, _match())).patch(
        f"/chat/matches/{MATCH_ID}/read", headers=AUTH_HEADERS
    )

    assert response.status_code == 200
    assert any("last_read_at" in patch for _, patch in calls.patches)
