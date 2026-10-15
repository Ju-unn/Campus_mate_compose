import json
import logging
import pathlib
import subprocess
import sys
from datetime import datetime

import httpx

from app.cards.push import FcmSender, PushToken, notify, send_pending
from app.cards.repository import CardRepository
from app.core.time import SEOUL


class _FakeCredentials:
    valid = True
    token = "ya29.test"


class _FakeRepo:
    def __init__(self, tokens, settings, status="active", pending=None):
        self._tokens, self._settings, self._status = tokens, settings, status
        self.deleted: list[str] = []
        # 밤에 보류된 알림(pending_pushes). 넣은 것과 아침에 지운 id 를 본다.
        self.pending: list[dict] = list(pending or [])
        self.pending_deleted: list[str] = []

    async def insert_pending_push(self, profile_id, kind, title, body, data):
        self.pending.append({"profile_id": profile_id, "kind": kind, "title": title, "body": body, "data": data})

    async def fetch_pending_pushes(self):
        return list(self.pending)

    async def delete_pending_pushes(self, ids):
        self.pending_deleted.extend(ids)

    async def fetch_profile_status(self, profile_id):
        return self._status

    async def fetch_push_tokens(self, profile_id):
        return list(self._tokens)

    async def fetch_notification_settings(self, profile_id):
        return dict(self._settings)

    async def delete_push_token(self, token, profile_id):
        self.deleted.append(token)


def _sender(handler) -> FcmSender:
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return FcmSender("campus-mate", client, credentials=_FakeCredentials())


async def test_send_posts_to_fcm_v1_with_bearer_token():
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json={"name": "projects/campus-mate/messages/1"})

    assert await _sender(handler).send("tok", "제목", "본문", {"route": "daily_card"}) == "sent"
    assert seen[0].url.path == "/v1/projects/campus-mate/messages:send"
    assert seen[0].headers["Authorization"] == "Bearer ya29.test"


async def test_send_asks_apns_to_deliver_a_visible_alert_now():
    """iOS 는 FCM 이 APNs 로 넘겨 준다. 조용한 알림이 아니라 소리 있는 일반 알림이고 우선순위 10(즉시)이어야 한다.
    안드로이드 블록은 그대로여야 한다."""
    seen: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(json.loads(request.content))
        return httpx.Response(200, json={})

    await _sender(handler).send("tok", "제목", "본문", {"route": "daily_card"})

    message = seen[0]["message"]
    assert message["apns"] == {"headers": {"apns-priority": "10"}, "payload": {"aps": {"sound": "default"}}}
    assert message["android"] == {"priority": "high"}


# 학생 인증 결과는 같은 종류끼리 한 장으로 합친다 — 앱이 관문을 지나면 tag 로 그 한 장을 지운다(core/push/foreground_push.dart).
_VERIFICATION_ANDROID = {"priority": "high", "notification": {"tag": "verification_result"}}
_VERIFICATION_APNS = {"headers": {"apns-priority": "10", "apns-collapse-id": "verification_result"},
                      "payload": {"aps": {"sound": "default"}}}


async def test_a_verification_result_carries_one_tag_so_the_next_one_replaces_it():
    """안드로이드는 notification.tag, iOS 는 apns-collapse-id 가 같으면 알림 줄의 앞 알림을 덮어쓴다."""
    sender, pushes = _recording_sender()

    await sender.send("tok", "학생 인증이 끝났어요", "본문", {"route": "verification"}, kind="verification_result")

    assert pushes[0]["android"] == _VERIFICATION_ANDROID
    assert pushes[0]["apns"] == _VERIFICATION_APNS


async def test_other_kinds_keep_their_android_and_apns_blocks():
    """매칭 · 채팅 · 카드 알림은 건마다 따로 쌓여야 한다 — tag 가 붙으면 앞 알림이 사라진다."""
    sender, pushes = _recording_sender()

    for kind in ("card_arrived", "acceptance_received", "match_made", "new_friend_review", "new_message",
                 "trust_reminder", ""):
        await sender.send("tok", "제목", "본문", {"route": "chat"}, kind=kind)

    assert {json.dumps(p["android"]) for p in pushes} == {json.dumps({"priority": "high"})}
    assert {json.dumps(p["apns"]) for p in pushes} == {
        json.dumps({"headers": {"apns-priority": "10"}, "payload": {"aps": {"sound": "default"}}})}


async def test_a_night_verification_result_sent_in_the_morning_keeps_its_tag():
    """22~8시에 보류한 학생 인증 결과도 아침 묶음 경로(send_pending → notify)로 같은 tag 를 달고 간다."""
    repo = _FakeRepo(["tok"], {}, pending=[_row("v1", "p1", "verification_result", "verification")])
    sender, pushes = _recording_sender()

    assert await send_pending(repo, sender, MORNING) == 1

    assert pushes[0]["android"] == _VERIFICATION_ANDROID
    assert pushes[0]["apns"] == _VERIFICATION_APNS


async def test_dead_token_is_reported_as_dead():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(404, json={"error": {"status": "NOT_FOUND"}})

    assert await _sender(handler).send("dead", "제목", "본문", {}) == "dead"


async def test_bad_request_is_our_fault_not_a_dead_token():
    """400 은 payload 가 잘못됐다는 뜻이다. 죽은 토큰으로 보고 지우면 멀쩡한 사람의 알림이 끊긴다."""
    repo = _FakeRepo(["살아있는-토큰"], {"acceptance_received": True, "quiet_hours": False})

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(400, json={"error": {"status": "INVALID_ARGUMENT"}})

    sent = await notify(repo, _sender(handler), "p1", "acceptance_received", "제목", "본문", {},
                        now=datetime(2026, 9, 21, 12, 0, tzinfo=SEOUL))

    assert sent == 0
    assert repo.deleted == []


async def test_notify_deletes_tokens_that_came_back_dead():
    repo = _FakeRepo(["dead"], {"acceptance_received": True, "quiet_hours": False})

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(404, json={})

    sent = await notify(repo, _sender(handler), "p1", "acceptance_received", "제목", "본문", {},
                        now=datetime(2026, 9, 21, 12, 0, tzinfo=SEOUL))

    assert sent == 0
    assert repo.deleted == ["dead"]


async def test_switched_off_kind_is_not_sent():
    repo = _FakeRepo(["tok"], {"acceptance_received": False, "quiet_hours": False})
    sent = await notify(repo, _sender(lambda r: httpx.Response(200, json={})), "p1",
                        "acceptance_received", "제목", "본문", {},
                        now=datetime(2026, 9, 21, 12, 0, tzinfo=SEOUL))
    assert sent == 0


async def test_quiet_hours_block_everything_except_the_card_alarm():
    """22~8시는 보류. 단 카드 도착은 지급 시각이 07:00 이라 예외다(계획서 실행 전 확인 6번)."""
    night = datetime(2026, 9, 21, 7, 0, tzinfo=SEOUL)
    repo = _FakeRepo(["tok"], {"acceptance_received": True, "card_arrived": True, "quiet_hours": True})
    handler = lambda request: httpx.Response(200, json={})

    assert await notify(repo, _sender(handler), "p1", "acceptance_received", "제", "본", {}, now=night) == 0
    assert await notify(repo, _sender(handler), "p1", "card_arrived", "제", "본", {}, now=night) == 1


async def test_chat_messages_ignore_quiet_hours_but_gate_reminders_do_not():
    """조각 5 결정 5(2026-09-22 사용자): 대화는 밤에도 오간다 — 채팅 푸시만 예외다.

    게이트 리마인드는 예외가 아니다. 대신 보낼 시각 자체를 아침으로 미뤄서(chat/gate.py 의
    reminder_at) 조용한 시간에 버려지지 않게 한다."""
    dawn = datetime(2026, 9, 22, 3, 0, tzinfo=SEOUL)
    repo = _FakeRepo(["tok"], {"new_message": True, "trust_reminder": True, "quiet_hours": True})
    handler = lambda request: httpx.Response(200, json={})

    assert await notify(repo, _sender(handler), "p1", "new_message", "제", "본", {}, now=dawn) == 1
    assert await notify(repo, _sender(handler), "p1", "trust_reminder", "제", "본", {}, now=dawn) == 0


async def test_a_suspended_recipient_gets_nothing_until_lifted():
    """조각 6: 정지 계정에는 어떤 푸시도 보내지 않는다. 모든 푸시가 notify() 를 지나서 여기 한 곳만 본다."""
    sent: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        sent.append(request)
        return httpx.Response(200, json={})

    noon = datetime(2026, 9, 21, 12, 0, tzinfo=SEOUL)
    on = {"new_message": True, "quiet_hours": False}

    suspended = _FakeRepo(["tok"], on, status="suspended")
    assert await notify(suspended, _sender(handler), "p1", "new_message", "제", "본", {}, now=noon) == 0
    assert sent == []

    lifted = _FakeRepo(["tok"], on, status="active")
    assert await notify(lifted, _sender(handler), "p1", "new_message", "제", "본", {}, now=noon) == 1


async def test_a_withdrawn_recipient_gets_nothing():
    """탈퇴 뒤 토큰 삭제는 best-effort 라 남아 있을 수 있다 — 관문이 상태로 한 번 더 막는다."""
    sent: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        sent.append(request)
        return httpx.Response(200, json={})

    noon = datetime(2026, 9, 21, 12, 0, tzinfo=SEOUL)
    withdrawn = _FakeRepo(["tok"], {"new_message": True, "quiet_hours": False}, status="withdrawn")

    assert await notify(withdrawn, _sender(handler), "p1", "new_message", "제", "본", {}, now=noon) == 0
    assert sent == []


# 밤 알림 보류 · 아침 묶음(결정 4 · B1, 사용자 2026-10-01) -------------------------------------

NIGHT = datetime(2026, 10, 3, 23, 0, tzinfo=SEOUL)
MORNING = datetime(2026, 10, 4, 8, 0, tzinfo=SEOUL)


def _row(id, owner, kind, route, title="원래 제목", body="원래 본문", **data):
    return {"id": id, "profile_id": owner, "kind": kind, "title": title, "body": body,
            "data": {"route": route, **data}}


def _recording_sender():
    pushes: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        pushes.append(json.loads(request.content)["message"])
        return httpx.Response(200, json={})

    return _sender(handler), pushes


async def test_a_night_acceptance_is_kept_for_the_morning():
    """예전에는 그냥 버렸다. 이제 보류 표에 원래 알림 그대로 넣고, 지금은 안 보낸다."""
    repo = _FakeRepo(["tok"], {"acceptance_received": True, "quiet_hours": True})
    sender, pushes = _recording_sender()

    sent = await notify(repo, sender, "p1", "acceptance_received", "대화 신청이 왔어요",
                        "A 님이 대화를 신청했어요", {"route": "acceptances", "card_id": "c1"}, now=NIGHT)

    assert sent == 0
    assert pushes == []
    assert repo.pending == [{"profile_id": "p1", "kind": "acceptance_received", "title": "대화 신청이 왔어요",
                             "body": "A 님이 대화를 신청했어요",
                             "data": {"route": "acceptances", "card_id": "c1"}}]


async def test_only_the_deferred_kinds_are_kept():
    """채팅 · 카드 도착은 예외라 바로 가고, 리마인드는 보낼 시각을 아침으로 미뤄 둬서 보류할 일이 없다."""
    repo = _FakeRepo(["tok"], {"trust_reminder": True, "new_message": True, "quiet_hours": True})
    sender, _ = _recording_sender()

    await notify(repo, sender, "p1", "trust_reminder", "제", "본", {}, now=NIGHT)
    await notify(repo, sender, "p1", "new_message", "제", "본", {}, now=NIGHT)

    assert repo.pending == []


async def test_a_switched_off_kind_is_not_kept_either():
    repo = _FakeRepo(["tok"], {"match_made": False, "quiet_hours": True})
    await notify(repo, _recording_sender()[0], "p1", "match_made", "제", "본", {}, now=NIGHT)
    assert repo.pending == []


async def test_a_single_kept_push_goes_out_as_it_was():
    repo = _FakeRepo(["tok"], {}, pending=[
        _row("r1", "p1", "match_made", "match", "매칭됐어요!", "A 님이 신청을 수락했어요.", match_id="m1"),
    ])
    sender, pushes = _recording_sender()

    assert await send_pending(repo, sender, MORNING) == 1

    assert pushes[0]["notification"] == {"title": "매칭됐어요!", "body": "A 님이 신청을 수락했어요."}
    assert pushes[0]["data"] == {"route": "match", "match_id": "m1"}
    assert repo.pending_deleted == ["r1"]


async def test_several_kept_pushes_of_one_kind_become_one_bundle():
    """사용자 결정 모양 "밤사이 2명이 대화를 신청했어요"(지시문 22 G). 묶음은 목록 화면으로 간다 — 어느 한 건으로 보내지 않는다."""
    repo = _FakeRepo(["tok"], {}, pending=[
        _row("r1", "p1", "acceptance_received", "acceptances", card_id="c1"),
        _row("r2", "p1", "acceptance_received", "acceptances", card_id="c2"),
    ])
    sender, pushes = _recording_sender()

    assert await send_pending(repo, sender, MORNING) == 1

    assert len(pushes) == 1
    assert pushes[0]["notification"] == {"title": "대화 신청이 왔어요", "body": "밤사이 2명이 대화를 신청했어요"}
    assert pushes[0]["data"] == {"route": "acceptances"}
    assert sorted(repo.pending_deleted) == ["r1", "r2"]


async def test_each_bundle_has_its_own_words():
    repo = _FakeRepo(["tok"], {}, pending=[
        _row("m1", "p1", "match_made", "match"), _row("m2", "p1", "match_made", "match"),
        _row("t1", "p1", "match_made", "chat", match_id="x"), _row("t2", "p1", "match_made", "chat", match_id="y"),
        _row("f1", "p1", "new_friend_review", "friend_reviews"),
        _row("f2", "p1", "new_friend_review", "friend_reviews"),
        _row("f3", "p1", "new_friend_review", "friend_reviews"),
    ])
    sender, pushes = _recording_sender()

    await send_pending(repo, sender, MORNING)

    bodies = {(p["data"]["route"], p["notification"]["title"], p["notification"]["body"]) for p in pushes}
    assert bodies == {
        ("match", "매칭됐어요!", "밤사이 2명과 매칭됐어요"),
        # 방 id 없이 보내면 앱이 그 방 대신 대화 목록을 연다(push_route.dart).
        ("chat", "카카오톡 아이디를 주고받았어요", "밤사이 2명과 프로필이 공개됐어요"),
        ("friend_reviews", "새 지인 리뷰가 도착했어요", "밤사이 리뷰 3개가 도착했어요"),
    }


async def test_friend_sign_ups_are_sent_one_by_one():
    """누구에게 리뷰를 쓸지가 알림마다 달라서 묶으면 갈 곳이 없어진다(대장 10-03 승인)."""
    repo = _FakeRepo(["tok"], {}, pending=[
        _row("s1", "p1", "new_friend_review", "friend_review_write", profile_id="a"),
        _row("s2", "p1", "new_friend_review", "friend_review_write", profile_id="b"),
    ])
    sender, pushes = _recording_sender()

    assert await send_pending(repo, sender, MORNING) == 2
    assert [p["data"]["profile_id"] for p in pushes] == ["a", "b"]


async def test_bundles_are_per_person():
    repo = _FakeRepo(["tok"], {}, pending=[
        _row("r1", "p1", "acceptance_received", "acceptances"),
        _row("r2", "p2", "acceptance_received", "acceptances"),
    ])
    sender, pushes = _recording_sender()

    assert await send_pending(repo, sender, MORNING) == 2
    assert {p["notification"]["body"] for p in pushes} == {"원래 본문"}


async def test_nothing_is_sent_or_dropped_while_it_is_still_quiet():
    repo = _FakeRepo(["tok"], {}, pending=[_row("r1", "p1", "match_made", "match")])
    sender, pushes = _recording_sender()

    assert await send_pending(repo, sender, datetime(2026, 10, 4, 7, 0, tzinfo=SEOUL)) == 0
    assert pushes == []
    assert repo.pending_deleted == []


async def test_a_switch_turned_off_overnight_wins_but_the_row_is_cleared():
    """아침에도 notify 를 다시 지난다 — 밤사이 끈 알림은 안 가고, 남겨 두면 매시 다시 볼 뿐이라 지운다."""
    repo = _FakeRepo(["tok"], {"match_made": False}, pending=[_row("r1", "p1", "match_made", "match")])
    sender, pushes = _recording_sender()

    assert await send_pending(repo, sender, MORNING) == 0
    assert pushes == []
    assert repo.pending_deleted == ["r1"]


async def test_one_failing_bundle_does_not_stop_the_others():
    repo = _FakeRepo(["tok"], {}, pending=[
        _row("r1", "p1", "match_made", "match"), _row("r2", "p2", "match_made", "match"),
    ])
    calls = 0

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        if calls == 1:
            raise httpx.ConnectError("네트워크 끊김")
        return httpx.Response(200, json={})

    assert await send_pending(repo, _sender(handler), MORNING) == 1
    # 실패한 묶음도 지운다 — 남기면 매시 같은 실패를 되풀이하거나 점심에 "밤사이" 알림이 간다.
    assert sorted(repo.pending_deleted) == ["r1", "r2"]


async def test_the_repository_keeps_and_clears_rows_through_postgrest():
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json=[])

    repo = CardRepository("https://x.supabase.co/rest/v1", "service-key",
                          httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    await repo.insert_pending_push("p1", "match_made", "제목", "본문", {"route": "match"})
    await repo.fetch_pending_pushes()
    await repo.delete_pending_pushes(["r1", "r2"])

    insert, fetch, delete = seen
    assert (insert.method, insert.url.path) == ("POST", "/rest/v1/pending_pushes")
    assert json.loads(insert.content) == {"profile_id": "p1", "kind": "match_made", "title": "제목",
                                          "body": "본문", "data": {"route": "match"}}
    # 먼저 온 것부터 — 한 건씩 보내는 친구 가입 알림이 온 순서대로 간다.
    assert fetch.url.params["order"] == "created_at"
    assert (delete.method, delete.url.params["id"]) == ("DELETE", "in.(r1,r2)")


async def test_a_night_verification_result_is_kept_too():
    """학생증 검토 결과(A7)는 조용한 시간 예외가 아니다 — 버리지 않고 보관함으로 간다(대장 10-03)."""
    repo = _FakeRepo(["tok"], {"quiet_hours": True})
    sender, pushes = _recording_sender()

    assert await notify(repo, sender, "p1", "verification_result", "학생증 검토가 끝났어요", "본",
                        {"route": "verification"}, now=NIGHT) == 0
    assert pushes == []
    assert [row["kind"] for row in repo.pending] == ["verification_result"]


async def test_verification_results_are_never_bundled():
    """같은 가는 화면이라도 kind 가 다르면 섞지 않고, 검토 결과는 여러 건이어도 한 건씩 간다."""
    repo = _FakeRepo(["tok"], {}, pending=[
        _row("v1", "p1", "verification_result", "friend_reviews", body="거절"),
        _row("v2", "p1", "verification_result", "friend_reviews", body="승인"),
    ])
    sender, pushes = _recording_sender()

    assert await send_pending(repo, sender, MORNING) == 2
    assert [p["notification"]["body"] for p in pushes] == ["거절", "승인"]


# ---- 전송 로그(진단용) ---------------------------------------------------------------------------------------------
# 합성 토큰이다. 로그에는 앞 6자와 길이만 남아야 하고 원문(특히 뒷부분)은 어디에도 없어야 한다.
_LOG_TOKEN = "fcmABC:APA91b-SYNTHETIC-TAIL-0123456789"
_LOG_TOKEN_MASK = f"fcmABC…({len(_LOG_TOKEN)})"
_APNS_401 = {"error": {
    "code": 401,
    "message": "APNs credential is invalid.",
    "status": "UNAUTHENTICATED",
    "details": [{"@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError", "errorCode": "THIRD_PARTY_AUTH_ERROR"}],
}}


def _log_text(caplog) -> str:
    return "\n".join(record.getMessage() for record in caplog.records)


async def test_failure_log_has_fcm_error_fields_and_masked_token(caplog):
    caplog.set_level(logging.INFO, logger="app.cards.push")
    sender = _sender(lambda request: httpx.Response(401, json=_APNS_401))

    result = await sender.send(_LOG_TOKEN, "제목-비밀", "본문-비밀", {}, kind="card_arrived", platform="ios")

    assert result == "failed"
    text = _log_text(caplog)
    for expected in ("401", "UNAUTHENTICATED", "APNs credential is invalid.", "THIRD_PARTY_AUTH_ERROR",
                     "kind=card_arrived", "platform=ios", _LOG_TOKEN_MASK):
        assert expected in text, expected
    assert _LOG_TOKEN not in text and "SYNTHETIC-TAIL" not in text
    assert "제목-비밀" not in text and "본문-비밀" not in text
    assert [record.levelno for record in caplog.records] == [logging.WARNING]


async def test_failure_log_scrubs_a_token_that_fcm_echoes_back(caplog):
    caplog.set_level(logging.INFO, logger="app.cards.push")
    echoed = {"error": {"code": 400, "status": "INVALID_ARGUMENT", "message": f"bad token {_LOG_TOKEN} here"}}
    sender = _sender(lambda request: httpx.Response(400, json=echoed))

    await sender.send(_LOG_TOKEN, "t", "b", {}, kind="new_message", platform="android")

    text = _log_text(caplog)
    assert "INVALID_ARGUMENT" in text and "SYNTHETIC-TAIL" not in text


async def test_failure_log_caps_a_long_message_at_300_chars(caplog):
    caplog.set_level(logging.INFO, logger="app.cards.push")
    long = {"error": {"code": 500, "status": "INTERNAL", "message": "x" * 2000}}
    sender = _sender(lambda request: httpx.Response(500, json=long))

    await sender.send(_LOG_TOKEN, "t", "b", {}, kind="k", platform="ios")

    detail = _log_text(caplog).split(" | ")[1]
    assert "INTERNAL" in detail and len(detail) <= 300


async def test_failure_log_for_non_json_response_keeps_first_200_chars(caplog):
    caplog.set_level(logging.INFO, logger="app.cards.push")
    sender = _sender(lambda request: httpx.Response(502, text="<html>" + "y" * 500))

    assert await sender.send(_LOG_TOKEN, "t", "b", {}, kind="k", platform="ios") == "failed"

    text = _log_text(caplog)
    assert "502" in text and "<html>" in text
    assert "y" * 200 not in text  # 앞 200자(여는 태그 6자 포함)에서 잘린다
    assert _LOG_TOKEN not in text


async def test_success_logs_one_info_line_without_token_body_or_title(caplog):
    caplog.set_level(logging.INFO, logger="app.cards.push")
    sender = _sender(lambda request: httpx.Response(200, json={"name": "projects/campus-mate/messages/1"}))

    assert await sender.send(_LOG_TOKEN, "제목-비밀", "본문-비밀", {}, kind="card_arrived", platform="android") == "sent"

    assert [(record.levelno, record.getMessage()) for record in caplog.records] == [
        (logging.INFO, f"FCM 전송 성공 kind=card_arrived platform=android token={_LOG_TOKEN_MASK}"),
    ]


async def test_notify_passes_kind_and_platform_from_the_token_row_to_the_log(caplog):
    caplog.set_level(logging.INFO, logger="app.cards.push")
    repo = _FakeRepo([PushToken(_LOG_TOKEN, "ios")], {"acceptance_received": True, "quiet_hours": False})
    sender = _sender(lambda request: httpx.Response(200, json={}))

    sent = await notify(repo, sender, "p1", "acceptance_received", "제목", "본문", {},
                        now=datetime(2026, 9, 21, 12, 0, tzinfo=SEOUL))

    assert sent == 1
    assert "kind=acceptance_received platform=ios" in _log_text(caplog)


def test_push_info_logs_reach_stderr_in_a_fresh_process():
    """운영(uvicorn)은 루트 로거에 핸들러가 없고 수준이 WARNING 이라 INFO 가 버려진다. 새 프로세스에서 실제로 찍히는지 본다."""
    code = "from app.cards.push import logger; logger.info('visible-probe')"
    backend = pathlib.Path(__file__).resolve().parents[2]
    done = subprocess.run([sys.executable, "-c", code], cwd=backend, capture_output=True, text=True, timeout=60)
    assert "visible-probe" in done.stderr, done.stderr
