import json
from datetime import datetime, timedelta

import httpx
import pytest
from fastapi.testclient import TestClient

from app.cards.push import FcmSender
from app.cards.repository import CardRepository
from app.chat.batch_router import run_chat_gate
from app.chat.repository import ChatRepository
from app.core.deps import get_client, get_settings
from app.core.time import SEOUL
from app.main import app
from app.settings import Settings

URL = "https://x.supabase.co/rest/v1"
MATCH_ID = "33333333-3333-3333-3333-333333333333"
A = "11111111-1111-1111-1111-111111111111"
B = "22222222-2222-2222-2222-222222222222"

# 리마인드 창은 매칭 24시간 뒤부터 한 시간이다. 20일 13:20 매칭 → 21일 13:20~14:20.
MATCHED_AT = datetime(2026, 9, 20, 13, 20, tzinfo=SEOUL)


class _FakeCredentials:
    valid = True
    token = "ya29.test"


def _settings(**overrides) -> Settings:
    return Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test", **overrides,
    )


def _match(**overrides) -> dict:
    participants = overrides.pop("participants", None) or [
        {"profile_id": A, "trust_response": None, "left_at": None, "last_read_at": None},
        {"profile_id": B, "trust_response": None, "left_at": None, "last_read_at": None},
    ]
    return {
        "id": MATCH_ID, "profile_a": A, "profile_b": B,
        "created_at": MATCHED_AT.isoformat(),
        "trust_passed_at": None, "chat_closed_at": None,
        "match_participants": participants, **overrides,
    }


class _Run:
    """배치 한 번을 돌리고 무슨 일이 있었는지 모아 준다."""

    def __init__(self, matches: list[dict], *, patch_rows: list[dict] | None = None):
        self.pushes: list[dict] = []
        self.patches: list[dict] = []
        self._matches = matches
        self._patch_rows = patch_rows

    def _handler(self, request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "fcm.googleapis.com" in url:
            self.pushes.append(json.loads(request.content)["message"])
            return httpx.Response(200, json={"name": "projects/x/messages/1"})
        if "/rest/v1/matches" in url:
            if request.method == "PATCH":
                self.patches.append(json.loads(request.content))
                return httpx.Response(200, json=self._patch_rows if self._patch_rows is not None
                                      else [{"id": MATCH_ID}])
            return httpx.Response(200, json=self._matches)
        if "/rest/v1/push_tokens" in url:
            return httpx.Response(200, json=[{"token": "tok"}])
        if "/rest/v1/notification_settings" in url:
            return httpx.Response(200, json=[])
        return httpx.Response(200, json=[])

    async def at(self, now: datetime) -> dict:
        client = httpx.AsyncClient(transport=httpx.MockTransport(self._handler))
        repo = ChatRepository(URL, "service-key", client)
        push_repo = CardRepository(URL, "service-key", client)
        sender = FcmSender("campus-mate", client, credentials=_FakeCredentials())
        return await run_chat_gate(repo, push_repo, sender, now)


async def test_nothing_happens_before_the_reminder_window():
    run = _Run([_match()])
    early = MATCHED_AT + timedelta(hours=23, minutes=40)
    assert await run.at(early) == {"reminded": 0, "closed": 0, "passed": 0}
    assert run.pushes == []


async def test_both_sides_are_reminded_inside_the_window():
    run = _Run([_match()])
    result = await run.at(datetime(2026, 9, 21, 14, 0, tzinfo=SEOUL))

    assert result == {"reminded": 2, "closed": 0, "passed": 0}
    assert run.pushes[0]["data"]["route"] == "chat"


async def test_the_window_closes_after_an_hour():
    run = _Run([_match()])
    assert (await run.at(datetime(2026, 9, 21, 15, 0, tzinfo=SEOUL)))["reminded"] == 0


async def test_a_dawn_window_is_moved_to_the_morning_batch():
    """새벽 창을 그대로 두면 조용한 시간에 버려지고, 창이 한 번뿐이라 영영 안 온다."""
    dawn = _match(created_at=datetime(2026, 9, 20, 3, 40, tzinfo=SEOUL).isoformat())

    assert (await _Run([dawn]).at(datetime(2026, 9, 21, 3, 0, tzinfo=SEOUL)))["reminded"] == 0
    assert (await _Run([dawn]).at(datetime(2026, 9, 21, 8, 0, tzinfo=SEOUL)))["reminded"] == 1 * 2


async def test_people_who_already_accepted_are_not_reminded():
    half = _match(participants=[
        {"profile_id": A, "trust_response": "accept", "left_at": None, "last_read_at": None},
        {"profile_id": B, "trust_response": None, "left_at": None, "last_read_at": None},
    ])
    assert (await _Run([half]).at(datetime(2026, 9, 21, 14, 0, tzinfo=SEOUL)))["reminded"] == 1


async def test_the_room_is_closed_once_the_deadline_passes():
    run = _Run([_match()])
    result = await run.at(MATCHED_AT + timedelta(hours=48, minutes=1))

    assert result == {"reminded": 0, "closed": 1, "passed": 0}
    # 닫는다 = 한 칸 찍기다. 메시지를 지우는 요청은 나가지 않는다(결정 3·4).
    assert run.patches == [{"chat_closed_at": (MATCHED_AT + timedelta(hours=48, minutes=1)).isoformat()}]


async def test_a_stranded_double_accept_is_stamped_instead_of_closed():
    """양쪽 다 수락했는데 도장이 없는 방은 닫지 않고 배치가 대신 찍는다(#77 리뷰 권고 1번).

    `/trust` 가 도장 직전에 끊기면 이 모양이 남는다. 닫아 버리면 되살릴 길이 없다."""
    stranded = _match(participants=[
        {"profile_id": A, "trust_response": "accept", "left_at": None, "last_read_at": None},
        {"profile_id": B, "trust_response": "accept", "left_at": None, "last_read_at": None},
    ])
    run = _Run([stranded])
    now = MATCHED_AT + timedelta(hours=49)

    assert await run.at(now) == {"reminded": 0, "closed": 0, "passed": 1}
    assert run.patches == [{"trust_passed_at": now.isoformat()}]


async def test_the_room_is_not_closed_a_minute_early():
    run = _Run([_match()])
    assert (await run.at(MATCHED_AT + timedelta(hours=47, minutes=59)))["closed"] == 0


async def test_rerunning_the_batch_does_not_count_the_same_room_twice():
    """재시도로 두 번 돌아도 이미 닫힌 방은 고쳐지지 않아 숫자가 늘지 않는다."""
    run = _Run([_match()], patch_rows=[])
    assert (await run.at(MATCHED_AT + timedelta(hours=49)))["closed"] == 0


async def test_a_room_someone_left_is_skipped_by_both_passes():
    """결정 7·11: 한쪽이 나간 방은 리마인드도 마감도 하지 않는다."""
    gone = _match(participants=[
        {"profile_id": A, "trust_response": None, "left_at": "2026-09-20T20:00:00+09:00",
         "last_read_at": None},
        {"profile_id": B, "trust_response": None, "left_at": None, "last_read_at": None},
    ])

    quiet = {"reminded": 0, "closed": 0, "passed": 0}
    assert await _Run([gone]).at(datetime(2026, 9, 21, 14, 0, tzinfo=SEOUL)) == quiet
    assert await _Run([gone]).at(MATCHED_AT + timedelta(hours=49)) == quiet


async def test_a_failing_push_does_not_stop_the_rest_of_the_run():
    run = _Run([_match()])
    original = run._handler

    def handler(request: httpx.Request) -> httpx.Response:
        if "fcm.googleapis.com" in str(request.url):
            raise httpx.ConnectError("네트워크 끊김")
        return original(request)

    run._handler = handler
    # 첫 사람의 알림이 터져도 두 번째 사람까지 돌고 200 으로 끝난다.
    assert await run.at(datetime(2026, 9, 21, 14, 0, tzinfo=SEOUL)) == {"reminded": 0, "closed": 0, "passed": 0}


# 엔드포인트 -------------------------------------------------------------------

@pytest.fixture
def secret_overrides():
    app.dependency_overrides[get_settings] = lambda: _settings(card_batch_secret="right")
    yield
    app.dependency_overrides.clear()


def test_the_batch_endpoint_requires_the_shared_secret(secret_overrides):
    client = TestClient(app)
    assert client.post("/batch/chat-gate").status_code == 401
    assert client.post("/batch/chat-gate", headers={"X-Batch-Secret": "wrong"}).status_code == 401


def test_the_batch_endpoint_runs_with_the_right_secret(secret_overrides):
    client = httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(200, json=[])))
    app.dependency_overrides[get_client] = lambda: client

    response = TestClient(app).post("/batch/chat-gate", headers={"X-Batch-Secret": "right"})

    assert response.status_code == 200
    assert response.json() == {"reminded": 0, "closed": 0, "passed": 0}


def test_the_batch_endpoint_is_closed_when_no_secret_is_configured():
    app.dependency_overrides[get_settings] = lambda: _settings(card_batch_secret="")
    try:
        assert TestClient(app).post(
            "/batch/chat-gate", headers={"X-Batch-Secret": ""}
        ).status_code == 401
    finally:
        app.dependency_overrides.clear()
