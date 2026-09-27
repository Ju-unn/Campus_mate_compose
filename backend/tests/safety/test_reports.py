"""신고(POST /reports). 처리 순서가 계약이다 — 대상 확인 → 하루 상한 → 스냅샷 → 차단 → 신고 → 디스코드 → 자동 가림."""
import logging
from datetime import timedelta

import httpx
import pytest

from app.core.deps import get_settings
from app.main import app
from fake_supabase import AUTH, MATCH_ID, ME, MESSAGE_ID, NOW, PARTNER, REPORT_WEBHOOK, STRANGER, settings

OTHER_A = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
OTHER_B = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
REPORT_ID = "66666666-6666-6666-6666-666666666666"


@pytest.fixture
def webhook(client):
    app.dependency_overrides[get_settings] = lambda: settings(discord_report_webhook_url=REPORT_WEBHOOK)


def _profile_report(**overrides) -> dict:
    return {"target_type": "profile", "target_id": PARTNER, "reason": "abuse", **overrides}


def _message_report(**overrides) -> dict:
    return {"target_type": "message", "target_id": MESSAGE_ID, "reason": "sexual", **overrides}


# 성공 --------------------------------------------------------------------------

def test_profile_report_stores_a_snapshot_of_storage_paths(client, world):
    response = client.post("/reports", json=_profile_report(), headers=AUTH)

    assert response.status_code == 201
    assert response.json() == {"ok": True}
    stored = world.reports[0]
    assert stored["reporter_id"] == ME
    assert stored["target_type"] == "profile"
    assert stored["target_id"] == PARTNER
    assert stored["target_profile_id"] == PARTNER
    assert stored["reason"] == "abuse"
    # 서명 URL 이 아니라 storage 경로다 — 서명 URL 은 만료돼 나중에 검토할 때 열리지 않는다.
    assert stored["target_snapshot"] == {
        "nickname": "여우비", "bio": "안녕하세요", "avatar_path": "p2/a.png",
        "photo_paths": ["p2/1.jpg", "p2/2.jpg"],
    }


def test_profile_snapshot_without_a_ready_avatar_has_null_path(client, world):
    world.profiles[PARTNER]["profile_avatars"] = [
        {"storage_path": "p2/fail.png", "status": "failed", "created_at": "2026-09-21T00:00:00+00:00"},
    ]
    client.post("/reports", json=_profile_report(), headers=AUTH)

    assert world.reports[0]["target_snapshot"]["avatar_path"] is None


def test_message_report_snapshots_the_bubble_and_targets_its_sender(client, world):
    response = client.post("/reports", json=_message_report(), headers=AUTH)

    assert response.status_code == 201
    stored = world.reports[0]
    assert stored["target_type"] == "message"
    assert stored["target_id"] == MESSAGE_ID
    assert stored["target_profile_id"] == PARTNER
    assert stored["target_snapshot"] == {
        "message_id": MESSAGE_ID, "match_id": MATCH_ID, "body": "기분 나쁜 말",
        "created_at": "2126-09-22T11:00:00+09:00",
    }


def test_reporting_also_blocks_and_leaves_the_room(client, world):
    client.post("/reports", json=_profile_report(), headers=AUTH)

    assert world.blocks[0]["blocker_id"] == ME
    assert world.blocks[0]["blocked_id"] == PARTNER
    assert world.posted_messages[0]["kind"] == "left"


def test_the_block_goes_out_before_the_report(client, world):
    """④ 차단 → ⑤ 신고. 신고가 먼저면 차단이 실패했을 때 '신고만 되고 차단은 안 된' 채로 갇힌다."""
    client.post("/reports", json=_profile_report(), headers=AUTH)

    assert world.log.index("POST blocks") < world.log.index("POST reports")


def test_a_past_match_whose_room_is_closed_can_still_be_reported(client, world):
    world.match["chat_closed_at"] = "2126-09-24T10:00:00+09:00"
    world.match["match_participants"][1]["left_at"] = "2126-09-23T10:00:00+09:00"

    assert client.post("/reports", json=_profile_report(), headers=AUTH).status_code == 201
    assert len(world.blocks) == 1
    assert world.posted_messages == []


# 신고 INSERT 실패 --------------------------------------------------------------

def test_a_duplicate_report_is_409_and_the_block_already_went_out(client, world):
    world.report_insert_status = 409
    world.report_insert_code = "23505"

    response = client.post("/reports", json=_profile_report(), headers=AUTH)

    assert response.status_code == 409
    assert response.json()["detail"] == "이미 신고한 사용자예요"
    assert world.log.index("POST blocks") < world.log.index("POST reports")
    assert len(world.blocks) == 1


def test_a_failing_report_insert_leaves_the_block_in_place(client, world):
    world.report_insert_status = 500

    with pytest.raises(httpx.HTTPStatusError):
        client.post("/reports", json=_profile_report(), headers=AUTH)

    assert len(world.blocks) == 1
    assert world.reports == []


# 하루 상한 ----------------------------------------------------------------------

def test_ten_reports_in_24_hours_is_429(client, world):
    world.recent_report_count = 10

    response = client.post("/reports", json=_profile_report(), headers=AUTH)

    assert response.status_code == 429
    assert response.json()["detail"] == "오늘은 더 신고할 수 없어요"
    # 상한에 걸리면 차단도 신고도 나가지 않는다(② 가 ④ 보다 앞).
    assert world.blocks == []
    assert world.calls("POST", "reports") == []
    query = world.calls("GET", "reports")[0].url.params
    assert query["reporter_id"] == f"eq.{ME}"
    assert query["created_at"] == f"gte.{(NOW - timedelta(hours=24)).isoformat()}"


def test_nine_reports_in_24_hours_is_still_allowed(client, world):
    world.recent_report_count = 9
    assert client.post("/reports", json=_profile_report(), headers=AUTH).status_code == 201


# 대상 확인 ----------------------------------------------------------------------

def test_reporting_someone_i_never_matched_is_404(client, world):
    response = client.post("/reports", json=_profile_report(target_id=STRANGER), headers=AUTH)

    assert response.status_code == 404
    assert response.json()["detail"] == "프로필을 찾을 수 없어요"
    assert world.blocks == []
    assert world.reports == []


def test_reporting_myself_is_404(client, world):
    response = client.post("/reports", json=_profile_report(target_id=ME), headers=AUTH)

    assert response.status_code == 404
    assert response.json()["detail"] == "프로필을 찾을 수 없어요"


@pytest.mark.parametrize("change", [
    pytest.param(lambda w: w.messages.clear(), id="없는 메시지"),
    pytest.param(lambda w: w.messages[MESSAGE_ID].update(sender_id=ME), id="내가 보낸 메시지"),
    pytest.param(lambda w: w.messages[MESSAGE_ID].update(kind="left"), id="시스템 줄"),
    pytest.param(lambda w: w.match.update(match_participants=[
        {"profile_id": PARTNER, "trust_response": None, "left_at": None, "last_read_at": None},
        {"profile_id": STRANGER, "trust_response": None, "left_at": None, "last_read_at": None},
    ]), id="내가 없는 방"),
])
def test_unreportable_messages_are_404(client, world, change):
    change(world)

    response = client.post("/reports", json=_message_report(), headers=AUTH)

    assert response.status_code == 404
    assert response.json()["detail"] == "메시지를 찾을 수 없어요"
    assert world.blocks == []
    assert world.reports == []


# 본문 검증 ----------------------------------------------------------------------

@pytest.mark.parametrize("note", [None, "", "   ", "가" * 201], ids=["없음", "빈칸", "공백", "201자"])
def test_other_needs_a_one_line_note(client, world, note):
    body = _profile_report(reason="other")
    if note is not None:
        body["reason_note"] = note

    assert client.post("/reports", json=body, headers=AUTH).status_code == 422
    assert world.blocks == []


def test_other_note_is_stored_trimmed_up_to_200(client, world):
    response = client.post("/reports", json=_profile_report(
        reason="other", reason_note=f"  {'가' * 200}  "), headers=AUTH)

    assert response.status_code == 201
    assert world.reports[0]["reason_note"] == "가" * 200


def test_a_note_on_another_reason_is_ignored(client, world):
    response = client.post("/reports", json=_profile_report(reason="spam", reason_note="광고예요"),
                           headers=AUTH)

    assert response.status_code == 201
    assert "reason_note" not in world.reports[0]


@pytest.mark.parametrize("body", [
    _profile_report(target_type="friend_review"),
    _profile_report(target_type="poll"),
    _profile_report(reason="rude"),
    _profile_report(target_id="not-a-uuid"),
], ids=["friend_review", "poll", "모르는 사유", "uuid 아님"])
def test_unknown_targets_and_reasons_are_422(client, world, body):
    assert client.post("/reports", json=body, headers=AUTH).status_code == 422
    assert world.blocks == []


# 디스코드 · 자동 가림 ----------------------------------------------------------------

def test_one_discord_line_per_report_with_ids_only(client, world, webhook):
    client.post("/reports", json=_message_report(), headers=AUTH)

    assert world.discord == [
        f"신고 1건 (신고: {REPORT_ID}, 대상: {PARTNER}, 사유: sexual, 누적 신고자: 1명). "
        "Supabase 대시보드에서 확인해 주세요."
    ]
    assert world.log.index("POST reports") < world.log.index("POST discord")


def test_discord_never_carries_the_snapshot(client, world, webhook):
    """2026-09-19 결정: 채널에 본문이 흐르면 웹훅 히스토리에 영구히 남는다."""
    world.open_reporters = [OTHER_A, OTHER_B]
    client.post("/reports", json=_message_report(), headers=AUTH)

    sent = "\n".join(world.discord)
    assert len(world.discord) == 2
    for secret in ("여우비", "나나", "기분 나쁜 말", "안녕하세요", "p2/", "storage"):
        assert secret not in sent


def test_the_third_open_reporter_hides_the_target_and_says_so(client, world, webhook):
    world.open_reporters = [OTHER_A, OTHER_B]

    assert client.post("/reports", json=_profile_report(), headers=AUTH).status_code == 201

    patch = world.calls("PATCH", "profiles")[0]
    assert patch.url.params["id"] == f"eq.{PARTNER}"
    # 조건부 PATCH — 이미 가려져 있으면 다시 찍지 않는다.
    assert patch.url.params["auto_hidden_at"] == "is.null"
    assert world.profiles[PARTNER]["auto_hidden_at"] == NOW.isoformat()
    assert len(world.discord) == 2
    assert "누적 신고자: 3명" in world.discord[0]
    assert world.discord[1] == (
        f"신고자 3명 도달 · 검토 필요 (대상: {PARTNER}). 카드에서 자동으로 가렸어요. "
        "정지하거나 auto_hidden_at 을 지워 주세요."
    )
    count = world.calls("GET", "reports")[-1].url.params
    assert count["target_profile_id"] == f"eq.{PARTNER}"
    # 운영자가 dismissed 로 닫은 신고는 세지 않는다 — 해제 뒤 한 건에 바로 다시 가려지지 않게.
    assert count["status"] == "eq.open"


def test_the_second_reporter_does_not_hide(client, world, webhook):
    world.open_reporters = [OTHER_A]

    client.post("/reports", json=_profile_report(), headers=AUTH)

    assert world.calls("PATCH", "profiles") == []
    assert len(world.discord) == 1
    assert "누적 신고자: 2명" in world.discord[0]


def test_one_person_reporting_a_profile_and_a_message_counts_once(client, world, webhook):
    world.open_reporters = [OTHER_A, OTHER_A]

    client.post("/reports", json=_profile_report(), headers=AUTH)

    assert world.calls("PATCH", "profiles") == []
    assert "누적 신고자: 2명" in world.discord[0]


def test_an_already_hidden_target_is_not_announced_again(client, world, webhook):
    world.open_reporters = [OTHER_A, OTHER_B, "cccccccc-cccc-cccc-cccc-cccccccccccc"]
    world.profiles[PARTNER]["auto_hidden_at"] = "2026-09-26T10:00:00+09:00"

    client.post("/reports", json=_profile_report(), headers=AUTH)

    assert world.profiles[PARTNER]["auto_hidden_at"] == "2026-09-26T10:00:00+09:00"
    assert len(world.discord) == 1


@pytest.mark.parametrize("fail", ["status", "raise"])
def test_a_failing_discord_does_not_fail_the_report(client, world, webhook, caplog, fail):
    if fail == "status":
        world.discord_status = 500
    else:
        world.discord_raises = True

    with caplog.at_level(logging.WARNING):
        response = client.post("/reports", json=_profile_report(), headers=AUTH)

    assert response.status_code == 201
    assert len(world.reports) == 1
    assert caplog.records
    # 웹훅 주소에는 토큰이 들어 있다 — 로그에 남기지 않는다.
    assert "secret-token" not in caplog.text


def test_a_failing_reporter_count_still_announces_the_report(client, world, webhook, caplog):
    """신고 · 차단은 이미 저장됐다. 여기서 500 이 나면 알림도 사라지고 재시도는 409 라 영영 안 온다."""
    world.open_reporters = [OTHER_A, OTHER_B]
    world.open_count_status = 500

    with caplog.at_level(logging.ERROR):
        response = client.post("/reports", json=_profile_report(), headers=AUTH)

    assert response.status_code == 201
    assert len(world.reports) == 1
    assert world.discord == [
        f"신고 1건 (신고: {REPORT_ID}, 대상: {PARTNER}, 사유: abuse, 누적 신고자: ?명). "
        "Supabase 대시보드에서 확인해 주세요."
    ]
    # 몇 명인지 모르면 가리지 않는다 — 다음 신고 때 다시 센다.
    assert world.calls("PATCH", "profiles") == []
    assert any(REPORT_ID in r.getMessage() for r in caplog.records if r.levelno >= logging.ERROR)


def test_an_empty_webhook_sends_nothing_and_warns(client, world, caplog):
    with caplog.at_level(logging.WARNING):
        response = client.post("/reports", json=_profile_report(), headers=AUTH)

    assert response.status_code == 201
    assert world.discord == []
    # 빈 주소로 post 가 나가도 예외가 삼켜져 201 이 된다 — 호스트로 단정해야 가드가 빠진 것을 잡는다.
    assert {r.url.host for r in world.requests} == {"x.supabase.co"}
    assert any(r.levelno == logging.WARNING and "웹훅이 비어 있어" in r.getMessage()
               for r in caplog.records)
