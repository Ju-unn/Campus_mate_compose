"""신뢰 확인 게이트에서 두 사람이 거의 같은 순간에 수락하는 경우(E-CHAT-44).

기존 chat 시험의 가짜 서버는 요청 하나만 보므로, 여기서는 방의 진짜 상태를 들고 있는 가짜 PostgREST 를 두고
스레드 두 개가 같은 방에 동시에 수락을 보낸다. 두 요청이 서로를 기다리는 자리(Barrier)를 정해 순서를 고정한다."""
import json
import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

import httpx
from fastapi import Depends
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
NOW = datetime(2026, 9, 22, 14, 0, tzinfo=SEOUL)
REVEAL_TITLE = "카카오톡 아이디를 주고받았어요"
TOKEN_OF = {"token-a": PROFILE_ID, "token-b": PARTNER_ID}


class _FakeCredentials:
    valid = True
    token = "ya29.test"


class _Room:
    """한 방의 진짜 상태를 들고 있는 가짜 PostgREST. 두 요청이 같은 상태를 읽고 쓴다.

    `sync_at` 번째 방 조회에서 두 요청이 서로를 기다린다.
    1: 둘 다 읽은 뒤에야 누구도 저장하지 못한다(옛 코드가 지는 자리).
    2: 둘 다 저장한 뒤에야 누구도 다시 읽지 못한다(둘 다 "통과" 를 보는 자리)."""

    def __init__(self, sync_at: int) -> None:
        self.lock = threading.Lock()
        self.responses: dict[str, str | None] = {PROFILE_ID: None, PARTNER_ID: None}
        self.passed_at: str | None = None
        self.stamps = 0
        self.pushes: list[str] = []
        self.sync_at = sync_at
        self.barrier = threading.Barrier(2, timeout=10)
        self.reads: dict[int, int] = {}

    def _match(self) -> dict:
        with self.lock:
            return {
                "id": MATCH_ID, "profile_a": PROFILE_ID, "profile_b": PARTNER_ID,
                "created_at": "2126-09-22T10:00:00+09:00",
                "trust_passed_at": self.passed_at, "chat_closed_at": None,
                "match_participants": [
                    {"profile_id": pid, "trust_response": response, "left_at": None, "last_read_at": None}
                    for pid, response in self.responses.items()
                ],
            }

    def _read(self) -> dict:
        # PostgREST 호출은 서비스 키로 가서 누가 불렀는지 헤더로 알 수 없다 — TestClient 하나가 스레드 하나라 스레드로 가른다.
        me = threading.get_ident()
        self.reads[me] = self.reads.get(me, 0) + 1
        syncing = self.reads[me] == self.sync_at
        if syncing and self.sync_at > 1:
            self.barrier.wait()  # 읽기 전에 기다린다 — 그 사이에 상대가 저장한 값까지 보인다
        match = self._match()
        if syncing and self.sync_at == 1:
            self.barrier.wait()  # 읽은 뒤에 기다린다 — 저장 전 값을 들고 상대를 기다린다
        return match

    def handle(self, request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        who = TOKEN_OF.get(request.headers.get("authorization", "").removeprefix("Bearer "), "")
        if "/auth/v1/user" in url:
            return httpx.Response(200, json={"id": who})
        if "student_verification" in url:
            return httpx.Response(200, json=[{"student_verification": "verified", "department": "컴공",
                                              "school_email_verified_at": "2026-10-01T00:00:00+00:00"}])
        if "fcm.googleapis.com" in url:
            self.pushes.append(json.loads(request.content)["message"]["notification"]["title"])
            return httpx.Response(200, json={"name": "projects/x/messages/1"})
        if "/rest/v1/matches" in url:
            if request.method == "PATCH":
                with self.lock:
                    if self.passed_at is not None:  # trust_passed_at is.null 조건
                        return httpx.Response(200, json=[])
                    self.passed_at = json.loads(request.content)["trust_passed_at"]
                    self.stamps += 1
                return httpx.Response(200, json=[{"id": MATCH_ID}])
            return httpx.Response(200, json=[self._read()])
        if "/rest/v1/match_participants" in url and request.method == "PATCH":
            target = request.url.params["profile_id"].removeprefix("eq.")
            with self.lock:
                if self.responses[target] is not None:  # trust_response is.null 조건
                    return httpx.Response(200, json=[])
                self.responses[target] = "accept"
            return httpx.Response(200, json=[{"profile_id": target}])
        if "/rest/v1/messages" in url and request.method == "POST":
            return httpx.Response(201, json=[{"id": "msg-1", **json.loads(request.content)}])
        if "/rest/v1/profile_private" in url:
            return httpx.Response(200, json=[{"kakao_id": "fox_rain"}])
        if "/rest/v1/profiles" in url:
            return httpx.Response(200, json=[{"id": PARTNER_ID, "nickname": "여우비", "profile_avatars": []}])
        if "/rest/v1/push_tokens" in url:
            return httpx.Response(200, json=[{"token": "tok"}])
        if "/rest/v1/notifications" in url and request.method == "POST":
            return httpx.Response(201)
        return httpx.Response(200, json=[])


def _both_accept_at_once(room: _Room) -> list[dict]:
    app.dependency_overrides[get_settings] = lambda: Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test",
    )
    app.dependency_overrides[get_now] = lambda: NOW
    # 요청마다 새 클라이언트 — 스레드 두 개가 이벤트 루프 하나를 같이 쓰지 않게 한다.
    app.dependency_overrides[get_client] = lambda: httpx.AsyncClient(transport=httpx.MockTransport(room.handle))
    app.dependency_overrides[router_module.get_sender] = lambda client=Depends(get_client): FcmSender(
        "campus-mate-test", client, credentials=_FakeCredentials())

    def accept(token: str) -> dict:
        response = TestClient(app).post(f"/chat/matches/{MATCH_ID}/trust",
                                        headers={"Authorization": f"Bearer {token}"})
        assert response.status_code == 200, response.text
        return response.json()

    try:
        with ThreadPoolExecutor(2) as pool:
            return list(pool.map(accept, TOKEN_OF))
    finally:
        app.dependency_overrides.clear()


def test_both_reading_before_either_saves_still_opens_the_gate():
    """E-CHAT-44: 수락이 수십 ms 안에 겹치면 둘 다 상대 값을 저장 전에 읽는다.
    저장한 뒤에 다시 읽지 않으면 둘 다 "상대 미응답" 이라 도장이 안 찍히고 양쪽이 기다림에 머문다."""
    room = _Room(sync_at=1)

    bodies = _both_accept_at_once(room)

    assert room.passed_at is not None
    assert room.stamps == 1
    assert any(body.get("kakao_id") == "fox_rain" for body in bodies)
    assert room.pushes.count(REVEAL_TITLE) == 2  # 양쪽에 한 번씩


def test_both_seeing_the_pass_still_stamps_and_announces_once():
    """둘 다 저장한 뒤 다시 읽으면 둘 다 "통과" 로 판정한다. 도장은 조건부라 한 쪽만 찍고, 공개 알림은 그쪽만 보낸다."""
    room = _Room(sync_at=2)

    bodies = _both_accept_at_once(room)

    assert room.stamps == 1
    assert all(body["passed"] is True for body in bodies)
    assert room.pushes.count(REVEAL_TITLE) == 2  # 양쪽에 한 번씩 — 넷이 아니다
