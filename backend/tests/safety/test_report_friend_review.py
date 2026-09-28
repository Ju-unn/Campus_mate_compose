"""지인 리뷰 신고(POST /reports, target_type=friend_review). 차단 · 자동 가림 없이 신고 행과 디스코드만(계획서 P1)."""
import httpx
import pytest

from app.core import errors
from app.core.deps import get_settings
from app.main import app
from app.safety.reasons import DAILY_REPORT_LIMIT
from fake_supabase import AUTH, ME, PARTNER, REPORT_WEBHOOK, settings

REVIEW_ID = "77777777-7777-7777-7777-777777777777"
OTHER_A = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
OTHER_B = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
# 작성자. 지인 리뷰 작성자는 매칭 상대일 필요가 없지만 fake 세상에 있는 프로필을 그대로 쓴다.
WRITER = PARTNER


@pytest.fixture
def webhook(client):
    app.dependency_overrides[get_settings] = lambda: settings(discord_report_webhook_url=REPORT_WEBHOOK)


@pytest.fixture
def reviews(world) -> dict[str, dict]:
    """fake_supabase.py 는 그대로 두고 이 세상에만 friend_reviews 표를 끼운다(handle 이 `_<표>` 로 찾는다)."""
    rows = {REVIEW_ID: {
        "id": REVIEW_ID, "reviewer_id": WRITER, "reviewee_id": ME, "tags": ["성실해요"],
        "comment": "믿음직해요", "status": "visible", "created_at": "2026-09-28T05:00:00+00:00",
    }}

    def table(method, params, body):
        row = rows.get(params.get("id", "").removeprefix("eq."))
        return httpx.Response(200, json=[row] if row else [])

    world._friend_reviews = table
    return rows


def _body(**overrides) -> dict:
    return {"target_type": "friend_review", "target_id": REVIEW_ID, "reason": "abuse", **overrides}


def test_friend_review_report_saves_snapshot_without_block(client, world, reviews):
    response = client.post("/reports", json=_body(), headers=AUTH)

    assert response.status_code == 201
    stored = world.reports[0]
    assert stored["target_type"] == "friend_review"
    assert stored["target_id"] == REVIEW_ID
    assert stored["target_profile_id"] == WRITER
    assert stored["target_snapshot"] == {
        "review_id": REVIEW_ID, "tags": ["성실해요"], "comment": "믿음직해요",
        "created_at": "2026-09-28T05:00:00+00:00",
    }
    # P1: 받은 사람이 작성자를 막으면 받은 사람에게만 사라진다 — 차단 · 방 나가기 없음.
    assert world.blocks == []
    assert world.posted_messages == []


@pytest.mark.parametrize("change", [{"reviewee_id": PARTNER}, {"status": "blinded"}])
def test_someone_elses_or_blinded_review_is_404(client, world, reviews, change):
    reviews[REVIEW_ID].update(change)

    response = client.post("/reports", json=_body(), headers=AUTH)

    assert response.status_code == 404
    assert response.json()["detail"] == errors.FRIEND_REVIEW_NOT_FOUND
    assert world.reports == []


def test_missing_review_is_404(client, world, reviews):
    reviews.clear()

    response = client.post("/reports", json=_body(), headers=AUTH)

    assert response.status_code == 404
    assert response.json()["detail"] == errors.FRIEND_REVIEW_NOT_FOUND


def test_friend_review_report_never_auto_hides(client, world, reviews, webhook):
    # 다른 두 사람 + 나 = 신고자 3명이어도 프로필 자동 가림을 찍지 않는다(결정 3). 디스코드는 한 줄.
    world.open_reporters = [OTHER_A, OTHER_B]

    client.post("/reports", json=_body(), headers=AUTH)

    assert world.auto_hide_patches == []
    assert len(world.discord) == 1


def test_friend_review_report_keeps_daily_limit(client, world, reviews):
    world.recent_report_count = DAILY_REPORT_LIMIT

    response = client.post("/reports", json=_body(), headers=AUTH)

    assert response.status_code == 429
    assert world.reports == []


def test_duplicate_friend_review_report_is_409(client, world, reviews):
    world.report_insert_status = 409
    world.report_insert_code = "23505"

    response = client.post("/reports", json=_body(), headers=AUTH)

    assert response.status_code == 409
    assert response.json()["detail"] == errors.ALREADY_REPORTED
