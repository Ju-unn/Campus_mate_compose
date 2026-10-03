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
        "id": POLL_ID, "author_id": AUTHOR, "question": "학식 vs 편의점", "option_a_label": "학식",
        "option_b_label": "편의점", "status": "visible", "created_at": "2026-10-01T03:00:00+00:00",
        "author": {"status": "active"},
    }}

    def table(method, params, body):
        assert method == "GET"
        # poll_votes 를 거치는 다대다가 하나 더 있어 힌트 없는 `profiles(...)` 는 실서버에서 300(PGRST201)이다.
        assert "author:profiles!polls_author_id_fkey(status)" in params["select"]
        row = rows.get(params.get("id", "").removeprefix("eq."))
        return httpx.Response(200, json=[row] if row else [])

    world._polls = table
    return rows


def _body(**overrides) -> dict:
    return {"target_type": "poll", "target_id": POLL_ID, "reason": "abuse", **overrides}


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
