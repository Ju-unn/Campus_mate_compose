"""투표 글 신고(POST /reports, target_type=poll, A16). 글쓴이는 익명이라 지인 리뷰처럼 차단 · 자동 가림 없이
신고 행과 디스코드만. 피드에 보이는 남의 글만 신고할 수 있다."""
import httpx
import pytest

from app.core import errors
from app.core.deps import get_settings
from app.main import app
from app.safety.reasons import DAILY_REPORT_LIMIT
from fake_supabase import AUTH, ME, PARTNER, REPORT_WEBHOOK, settings

POLL_ID = "88888888-8888-8888-8888-888888888888"
OTHER_A = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
OTHER_B = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
# 글쓴이. 투표 글쓴이는 매칭 상대일 필요가 없지만 fake 세상에 있는 프로필을 그대로 쓴다.
AUTHOR = PARTNER


@pytest.fixture
def webhook(client):
    app.dependency_overrides[get_settings] = lambda: settings(discord_report_webhook_url=REPORT_WEBHOOK)


@pytest.fixture
def polls(world) -> dict[str, dict]:
    """fake_supabase.py 는 그대로 두고 이 세상에만 polls 표를 끼운다(handle 이 `_<표>` 로 찾는다)."""
    rows = {POLL_ID: {
        "id": POLL_ID, "author_id": AUTHOR, "kind": "poll", "category": "free", "question": "학식 vs 편의점",
        "option_a_label": "학식", "option_b_label": "편의점", "status": "visible",
        "created_at": "2026-10-01T03:00:00+00:00", "author": {"status": "active"},
    }}

    def table(method, params, body):
        assert method == "GET"
        # poll_votes 를 거치는 다대다가 하나 더 있어 힌트 없는 `profiles(...)` 는 실서버에서 300(PGRST201)이다.
        assert "author:profiles!polls_author_id_fkey(status)" in params["select"]
        # 이 가짜는 select 와 상관없이 줄 전체를 준다 — 게시물 스냅샷에 쓰는 두 칸을 실제로 읽는지 여기서 본다.
        assert {"kind", "category"} <= set(params["select"].split(","))
        row = rows.get(params.get("id", "").removeprefix("eq."))
        return httpx.Response(200, json=[row] if row else [])

    world._polls = table
    return rows


def _body(**overrides) -> dict:
    return {"target_type": "poll", "target_id": POLL_ID, "reason": "abuse", **overrides}


def test_post_report_snapshot_adds_kind_and_category_with_null_options(client, world, polls):
    # 게시물(할 일 19)도 target_type 은 poll 그대로다. 투표 스냅샷 모양은 바뀌지 않고 게시물만 두 칸이 더 붙는다.
    polls[POLL_ID].update(kind="post", category="love", question="오늘 고백했어요",
                          option_a_label=None, option_b_label=None)

    response = client.post("/reports", json=_body(), headers=AUTH)

    assert response.status_code == 201
    assert world.reports[0]["target_type"] == "poll"
    assert world.reports[0]["target_snapshot"] == {
        "poll_id": POLL_ID, "question": "오늘 고백했어요", "option_a_label": None, "option_b_label": None,
        "created_at": "2026-10-01T03:00:00+00:00", "kind": "post", "category": "love",
    }


def test_poll_report_saves_snapshot_without_block(client, world, polls):
    response = client.post("/reports", json=_body(), headers=AUTH)

    assert response.status_code == 201
    stored = world.reports[0]
    assert stored["target_type"] == "poll"
    assert stored["target_id"] == POLL_ID
    assert stored["target_profile_id"] == AUTHOR
    assert stored["target_snapshot"] == {
        "poll_id": POLL_ID, "question": "학식 vs 편의점", "option_a_label": "학식",
        "option_b_label": "편의점", "created_at": "2026-10-01T03:00:00+00:00",
    }
    # 익명 글쓴이 — 매칭 상대가 아니라 차단 · 방 나가기가 없다.
    assert world.blocks == []
    assert world.posted_messages == []


@pytest.mark.parametrize("change", [
    {"author_id": ME},
    {"status": "blinded"},
    {"author": {"status": "suspended"}},
], ids=["내 글", "가려진 글", "글쓴이 정지"])
def test_my_own_blinded_or_hidden_author_poll_is_404(client, world, polls, change):
    polls[POLL_ID].update(change)

    response = client.post("/reports", json=_body(), headers=AUTH)

    assert response.status_code == 404
    assert response.json()["detail"] == errors.POLL_NOT_FOUND
    assert world.reports == []


def test_missing_poll_is_404(client, world, polls):
    polls.clear()

    response = client.post("/reports", json=_body(), headers=AUTH)

    assert response.status_code == 404
    assert response.json()["detail"] == errors.POLL_NOT_FOUND


def test_poll_report_never_auto_hides(client, world, polls, webhook):
    # 다른 두 사람 + 나 = 신고자 3명이어도 프로필 자동 가림을 찍지 않는다. 글 가림은 운영자가 대시보드에서. 디스코드는 한 줄.
    world.open_reporters = [OTHER_A, OTHER_B]

    client.post("/reports", json=_body(), headers=AUTH)

    assert world.auto_hide_patches == []
    assert len(world.discord) == 1


def test_poll_report_keeps_daily_limit(client, world, polls):
    world.recent_report_count = DAILY_REPORT_LIMIT

    response = client.post("/reports", json=_body(), headers=AUTH)

    assert response.status_code == 429
    assert world.reports == []


def test_duplicate_poll_report_is_409(client, world, polls):
    world.report_insert_status = 409
    world.report_insert_code = "23505"

    response = client.post("/reports", json=_body(), headers=AUTH)

    assert response.status_code == 409
    assert response.json()["detail"] == errors.ALREADY_REPORTED


# 공지(할 일 21)도 target_type 은 poll 그대로다. 글쓴이가 없다 — 작성자 active · 본인 검사를 건너뛰고 target_profile_id 는 null.
def _notice(polls) -> None:
    polls[POLL_ID].update(author_id=None, author=None, kind="notice", category="free", title="서비스 점검 안내",
                          question="점검 본문", option_a_label=None, option_b_label=None)


def test_notice_report_has_no_target_profile_and_snapshots_kind_title_and_body(client, world, polls):
    _notice(polls)

    response = client.post("/reports", json=_body(), headers=AUTH)

    assert response.status_code == 201
    stored = world.reports[0]
    assert stored["target_type"] == "poll"
    assert stored["target_profile_id"] is None
    assert stored["target_snapshot"] == {
        "poll_id": POLL_ID, "question": "점검 본문", "option_a_label": None, "option_b_label": None,
        "created_at": "2026-10-01T03:00:00+00:00", "kind": "notice", "title": "서비스 점검 안내",
    }
    assert world.blocks == []
    assert world.auto_hide_patches == []


def test_notice_report_does_not_count_reporters_of_a_missing_target(client, world, polls, webhook):
    # 공지는 신고당한 사람이 없다 — `target_profile_id=eq.None` 같은 엉뚱한 세기 요청을 보내지 않는다.
    _notice(polls)

    client.post("/reports", json=_body(), headers=AUTH)

    counts = [r for r in world.requests if r.method == "GET" and r.url.path.endswith("/reports")
              and "target_profile_id" in r.url.params]
    assert counts == []
    # 디스코드 한 줄은 사람이 읽는 말로 — "대상: None" 이 아니다.
    (line,) = world.discord
    assert "대상: 운영자 공지" in line
    assert "None" not in line
    assert "누적 신고자: 0명" in line


def test_notice_report_reads_kind_and_title(client, world, polls):
    _notice(polls)
    seen: list[str] = []
    table = world._polls

    def spy(method, params, body):
        seen.append(params["select"])
        return table(method, params, body)

    world._polls = spy
    client.post("/reports", json=_body(), headers=AUTH)

    assert {"kind", "title"} <= set(seen[0].split(","))


def test_blinded_notice_report_is_404(client, world, polls):
    _notice(polls)
    polls[POLL_ID]["status"] = "blinded"

    response = client.post("/reports", json=_body(), headers=AUTH)

    assert response.status_code == 404
    assert world.reports == []
