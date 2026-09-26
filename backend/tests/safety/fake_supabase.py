"""조각 6 안전(신고 · 차단 · 14c) 테스트가 같이 쓰는 PostgREST 가짜.

요청은 URL 부분 문자열이 아니라 **경로의 테이블 이름 + params 키**로 가른다
(메모 reference_backend_test_mock_traps ①). 상태를 들고 있어 "두 번 차단" 처럼 앞 요청이
뒤 요청의 답을 바꾸는 흐름도 그대로 흉내 낸다.
"""
import json
from datetime import datetime

import httpx

from app.core.time import SEOUL
from app.settings import Settings

ME = "11111111-1111-1111-1111-111111111111"
PARTNER = "22222222-2222-2222-2222-222222222222"
MATCH_ID = "33333333-3333-3333-3333-333333333333"
STRANGER = "44444444-4444-4444-4444-444444444444"
MESSAGE_ID = "55555555-5555-5555-5555-555555555555"
AUTH = {"Authorization": "Bearer valid-token"}
REPORT_WEBHOOK = "https://discord.com/api/webhooks/report/secret-token"
NOW = datetime(2026, 9, 27, 14, 0, tzinfo=SEOUL)


def settings(**overrides) -> Settings:
    return Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test", **overrides,
    )


def _participant(profile_id: str, **overrides) -> dict:
    return {"profile_id": profile_id, "trust_response": None, "left_at": None,
            "last_read_at": None, **overrides}


class FakeSupabase:
    """나(ME)와 상대(PARTNER) 사이에 매칭 하나가 있는 세상."""

    def __init__(self) -> None:
        self.log: list[str] = []            # "POST blocks" 처럼 요청 순서
        self.requests: list[httpx.Request] = []
        self.caller = ME                    # 로그인한 사람. 상대가 나가거나 막는 장면은 PARTNER 로 바꿔 부른다
        self.my_status = "active"
        self.match: dict | None = {
            "id": MATCH_ID, "profile_a": ME, "profile_b": PARTNER,
            "created_at": "2126-09-22T10:00:00+09:00",
            "trust_passed_at": None, "chat_closed_at": None,
            "match_participants": [_participant(ME), _participant(PARTNER)],
        }
        self.profiles: dict[str, dict] = {
            ME: {"id": ME, "nickname": "나나", "status": "active", "auto_hidden_at": None,
                 "bio": "내 소개", "profile_avatars": []},
            PARTNER: {
                "id": PARTNER, "nickname": "여우비", "birth_year": 2003, "major": "컴퓨터공학과",
                "status": "active", "auto_hidden_at": None, "bio": "안녕하세요",
                "animal_type": "cat", "impression_type": "cute", "interest_tags": ["영화"],
                "my_traits": ["조용한"], "ideal_traits": ["다정한"], "ideal_note": "같이 영화 보는 사람",
                "height_cm": 165, "mbti": "INFP", "student_number": "20", "religion": "none",
                "is_smoker": False, "universities": {"name": "테스트대학교"},
                "profile_avatars": [
                    {"storage_path": "p2/old.png", "status": "ready", "created_at": "2026-09-19T00:00:00+00:00"},
                    {"storage_path": "p2/a.png", "status": "ready", "created_at": "2026-09-20T00:00:00+00:00"},
                    {"storage_path": "p2/fail.png", "status": "failed", "created_at": "2026-09-21T00:00:00+00:00"},
                ],
            },
        }
        self.photo_paths: dict[str, list[str]] = {PARTNER: ["p2/1.jpg", "p2/2.jpg"]}
        self.kakao_ids: dict[str, str] = {ME: "my_id", PARTNER: "fox_rain"}
        self.messages: dict[str, dict] = {
            MESSAGE_ID: {"id": MESSAGE_ID, "match_id": MATCH_ID, "sender_id": PARTNER, "kind": "text",
                         "body": "기분 나쁜 말", "created_at": "2126-09-22T11:00:00+09:00"},
        }
        self.blocks: list[dict] = []        # {blocker_id, blocked_id, created_at}
        self.posted_messages: list[dict] = []
        self.reports: list[dict] = []       # 넣은 신고 본문
        self.recent_report_count = 0        # 최근 24시간 내 신고 수(하루 상한 조회가 받는 행 수)
        self.open_reporters: list[str] = [] # 대상에게 이미 들어와 있던 open 신고의 reporter_id
        self.open_count_status = 200        # open 신고자 세기 조회의 응답 코드(실패 흉내)
        self.report_insert_status = 201
        self.report_insert_code: str | None = None
        self.auto_hide_patches: list[httpx.QueryParams] = []
        self.discord: list[str] = []
        self.discord_status = 204
        self.discord_raises = False

    # ------------------------------------------------------------------
    def handle(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        url = request.url
        if url.host == "discord.com":
            self.log.append("POST discord")
            if self.discord_raises:
                raise httpx.ConnectError("네트워크 끊김")
            self.discord.append(json.loads(request.content)["content"])
            return httpx.Response(self.discord_status)
        if url.path == "/auth/v1/user":
            return httpx.Response(200, json={"id": self.caller})
        if url.path.startswith("/storage/v1/object/sign/profile-photos/"):
            path = url.path.removeprefix("/storage/v1/object/sign/profile-photos/")
            return httpx.Response(200, json={"signedURL": f"/object/sign/profile-photos/{path}?token=t"})
        table = url.path.removeprefix("/rest/v1/")
        self.log.append(f"{request.method} {table}")
        params = url.params
        body = json.loads(request.content) if request.content else None
        return getattr(self, f"_{table}")(request.method, params, body)

    def _eq(self, params: httpx.QueryParams, key: str) -> str | None:
        value = params.get(key)
        return value.removeprefix("eq.") if value else None

    # 테이블별 ----------------------------------------------------------------
    def _profiles(self, method, params, body):
        profile_id = self._eq(params, "id")
        if method == "PATCH":
            # 자동 가림 조건부 PATCH — auto_hidden_at=is.null 이면 이미 찍힌 행은 고치지 않는다.
            self.auto_hide_patches.append(params)
            row = self.profiles[profile_id]
            if params.get("auto_hidden_at") == "is.null" and row["auto_hidden_at"] is not None:
                return httpx.Response(200, json=[])
            row.update(body)
            return httpx.Response(200, json=[row])
        select = params.get("select", "")
        if "student_verification" in select:
            return httpx.Response(200, json=[{"student_verification": "verified", "department": "컴공",
                                              "status": self.my_status}])
        row = self.profiles.get(profile_id)
        return httpx.Response(200, json=[row] if row else [])

    def _matches(self, method, params, body):
        match = self.match
        if match is None:
            return httpx.Response(200, json=[])
        if "id" in params:
            return httpx.Response(200, json=[match] if self._eq(params, "id") == match["id"] else [])
        pair = (self._eq(params, "profile_a"), self._eq(params, "profile_b"))
        return httpx.Response(200, json=[match] if pair == (match["profile_a"], match["profile_b"]) else [])

    def _match_participants(self, method, params, body):
        assert method == "PATCH"
        profile_id = self._eq(params, "profile_id")
        row = next(p for p in self.match["match_participants"] if p["profile_id"] == profile_id)
        if params.get("left_at") == "is.null" and row["left_at"] is not None:
            return httpx.Response(200, json=[])
        row.update(body)
        return httpx.Response(200, json=[row])

    def _messages(self, method, params, body):
        if method == "POST":
            self.posted_messages.append(body)
            return httpx.Response(201, json=[{"id": "msg-new", **body}])
        row = self.messages.get(self._eq(params, "id"))
        return httpx.Response(200, json=[row] if row else [])

    def _blocks(self, method, params, body):
        if method == "POST":
            if not any(b["blocker_id"] == body["blocker_id"] and b["blocked_id"] == body["blocked_id"]
                       for b in self.blocks):
                self.blocks.append({**body, "created_at": "2026-09-27T10:00:00+09:00"})
            return httpx.Response(201)
        if method == "DELETE":
            blocker, blocked = self._eq(params, "blocker_id"), self._eq(params, "blocked_id")
            self.blocks = [b for b in self.blocks
                           if not (b["blocker_id"] == blocker and b["blocked_id"] == blocked)]
            return httpx.Response(204)
        if "or" in params:
            # 카드 · 14c 가 보는 양방향 조회 — (blocker_id.eq.X,blocked_id.eq.X)
            rows = [b for b in self.blocks if ME in (b["blocker_id"], b["blocked_id"])]
            return httpx.Response(200, json=[{"blocker_id": b["blocker_id"], "blocked_id": b["blocked_id"]}
                                             for b in rows])
        blocker = self._eq(params, "blocker_id")
        rows = [
            {"blocked_id": b["blocked_id"], "created_at": b["created_at"],
             "profile": {"nickname": self.profiles[b["blocked_id"]]["nickname"],
                         "profile_avatars": self.profiles[b["blocked_id"]]["profile_avatars"]}}
            for b in self.blocks if b["blocker_id"] == blocker
        ]
        return httpx.Response(200, json=rows)

    def _reports(self, method, params, body):
        if method == "POST":
            if self.report_insert_status >= 400:
                payload = {"code": self.report_insert_code} if self.report_insert_code else {}
                return httpx.Response(self.report_insert_status, json=payload)
            self.reports.append(body)
            return httpx.Response(201, json=[{"id": "66666666-6666-6666-6666-666666666666", **body}])
        if "reporter_id" in params:
            return httpx.Response(200, json=[{"id": f"r{i}"} for i in range(self.recent_report_count)])
        if self.open_count_status >= 400:
            return httpx.Response(self.open_count_status, json={})
        reporters = self.open_reporters + [r["reporter_id"] for r in self.reports]
        return httpx.Response(200, json=[{"reporter_id": r} for r in reporters])

    def _profile_photos(self, method, params, body):
        paths = self.photo_paths.get(self._eq(params, "profile_id"), [])
        return httpx.Response(200, json=[{"storage_path": p, "position": i} for i, p in enumerate(paths)])

    def _profile_private(self, method, params, body):
        kakao = self.kakao_ids.get(self._eq(params, "profile_id"))
        return httpx.Response(200, json=[{"kakao_id": kakao}] if kakao else [])

    def _daily_cards(self, method, params, body):
        # 10b 카드 상세와 14c 가 같은 몸통을 쓰는지 대조할 때만 쓴다 — 내가 받은 상대 카드 한 장.
        return httpx.Response(200, json=[{
            "id": "card-1", "owner_id": ME, "target_id": PARTNER, "source": "daily",
            "issued_at": "2026-09-27T07:00:00+09:00", "expires_at": "2126-09-30T07:00:00+09:00",
            "card_decisions": None, "acceptance_responses": None,
        }])

    def _survey_answers(self, method, params, body):
        return httpx.Response(200, json=[{"axis": 1, "value": 0.5}])

    def _notification_settings(self, method, params, body):
        return httpx.Response(200, json=[])

    def _push_tokens(self, method, params, body):
        return httpx.Response(200, json=[])

    # 도우미 ------------------------------------------------------------------
    def calls(self, method: str, table: str) -> list[httpx.Request]:
        return [r for r in self.requests
                if r.method == method and r.url.path == f"/rest/v1/{table}"]
