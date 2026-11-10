"""O/X 글 댓글 신고(POST /reports, target_type=poll_comment). 댓글 작성자는 익명이라 투표 글처럼 차단 · 자동 가림 없이
신고 행과 디스코드만. 보이는 글의 보이는 남의 댓글만 신고할 수 있다."""
import httpx
import pytest

from app.core import errors
from app.core.deps import get_settings
from app.main import app
from app.safety.reasons import DAILY_REPORT_LIMIT
from fake_supabase import AUTH, ME, PARTNER, REPORT_WEBHOOK, settings

COMMENT_ID = "77777777-7777-7777-7777-777777777777"
POLL_ID = "88888888-8888-8888-8888-888888888888"
OTHER_A = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
OTHER_B = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
# 댓글 작성자. 매칭 상대일 필요는 없지만 fake 세상에 있는 프로필을 그대로 쓴다.
COMMENTER = PARTNER


@pytest.fixture
def webhook(client):
    app.dependency_overrides[get_settings] = lambda: settings(discord_report_webhook_url=REPORT_WEBHOOK)


@pytest.fixture
def comments(world) -> dict[str, dict]:
    """fake_supabase.py 는 그대로 두고 이 세상에만 poll_comments 표를 끼운다(handle 이 `_<표>` 로 찾는다)."""
    rows = {COMMENT_ID: {
        "id": COMMENT_ID, "poll_id": POLL_ID, "author_id": COMMENTER, "body": "그건 좀 아니죠", "status": "visible",
        "created_at": "2026-11-10T03:00:00+00:00",
        "author": {"status": "active"},
        "poll": {"status": "visible", "author": {"status": "active"}},
    }}

    def table(method, params, body):
        assert method == "GET"
        # 댓글 ↔ 프로필 · 글 ↔ 프로필은 FK 가 여러 개(poll_votes 를 거치는 다대다 포함)라 힌트 없는 임베드는 300(PGRST201)이다.
        select = params["select"]
        assert "author:profiles!poll_comments_author_id_fkey(status)" in select
        assert "poll:polls!poll_comments_poll_id_fkey(status,author:profiles!polls_author_id_fkey(status))" in select
        row = rows.get(params.get("id", "").removeprefix("eq."))
        return httpx.Response(200, json=[row] if row else [])

    world._poll_comments = table
    return rows


def _body(**overrides) -> dict:
    return {"target_type": "poll_comment", "target_id": COMMENT_ID, "reason": "abuse", **overrides}


def test_comment_report_saves_snapshot_without_block(client, world, comments):
    response = client.post("/reports", json=_body(), headers=AUTH)

    assert response.status_code == 201
    stored = world.reports[0]
    assert stored["target_type"] == "poll_comment"
    assert stored["target_id"] == COMMENT_ID
    assert stored["target_profile_id"] == COMMENTER
    assert stored["target_snapshot"] == {
        "comment_id": COMMENT_ID, "poll_id": POLL_ID, "body": "그건 좀 아니죠", "created_at": "2026-11-10T03:00:00+00:00",
    }
    # 익명 작성자 — 매칭 상대가 아니라 차단 · 방 나가기가 없다.
    assert world.blocks == []
    assert world.posted_messages == []


@pytest.mark.parametrize("change", [
    {"author_id": ME},
    {"status": "blinded"},
    {"author": {"status": "suspended"}},
    {"poll": {"status": "blinded", "author": {"status": "active"}}},
    {"poll": {"status": "visible", "author": {"status": "withdrawn"}}},
], ids=["내 댓글", "가려진 댓글", "댓글 작성자 정지", "가려진 글", "글쓴이 탈퇴"])
def test_my_own_blinded_or_hidden_comment_is_404(client, world, comments, change):
    comments[COMMENT_ID].update(change)

    response = client.post("/reports", json=_body(), headers=AUTH)

    assert response.status_code == 404
    assert response.json()["detail"] == errors.POLL_COMMENT_NOT_FOUND
    assert world.reports == []


def test_missing_comment_is_404(client, world, comments):
    comments.clear()

    response = client.post("/reports", json=_body(), headers=AUTH)

    assert response.status_code == 404
    assert response.json()["detail"] == errors.POLL_COMMENT_NOT_FOUND


def test_comment_report_never_auto_hides(client, world, comments, webhook):
    # 다른 두 사람 + 나 = 신고자 3명이어도 프로필 자동 가림을 찍지 않는다. 댓글 가림은 운영자가 대시보드에서. 디스코드는 한 줄.
    world.open_reporters = [OTHER_A, OTHER_B]

    client.post("/reports", json=_body(), headers=AUTH)

    assert world.auto_hide_patches == []
    assert len(world.discord) == 1


def test_comment_report_keeps_daily_limit(client, world, comments):
    world.recent_report_count = DAILY_REPORT_LIMIT

    response = client.post("/reports", json=_body(), headers=AUTH)

    assert response.status_code == 429
    assert world.reports == []


def test_duplicate_comment_report_is_409(client, world, comments):
    world.report_insert_status = 409
    world.report_insert_code = "23505"

    response = client.post("/reports", json=_body(), headers=AUTH)

    assert response.status_code == 409
    assert response.json()["detail"] == errors.ALREADY_REPORTED
