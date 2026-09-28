"""정리 배치 `POST /batch/cleanup`(B3 · B4). 매일 04:00 Asia/Seoul, 처음부터 OIDC 로 부른다(DEPLOY.md)."""
import logging
from datetime import timedelta

from account_world import BUCKETS, INFINITY, NOW, OLD, RECENT

SECRET = {"X-Batch-Secret": "right"}


def _run(client) -> dict:
    response = client.post("/batch/cleanup", headers=SECRET)
    assert response.status_code == 200
    return response.json()


def test_31_days_after_withdrawal_the_account_goes_but_29_days_stays(client, world):
    world.withdrawn(OLD, days_ago=31)
    world.withdrawn(RECENT, days_ago=29)

    result = _run(client)

    assert result["deleted_accounts"] == 1
    assert result["skipped_accounts"] == 0
    # auth 사용자를 지운다 — profiles 는 cascade(편차 2). 파일은 버킷 셋 모두에서 먼저 지운다.
    assert len(world.calls("DELETE", f"/auth/v1/admin/users/{OLD}")) == 1
    assert world.calls("DELETE", f"/auth/v1/admin/users/{RECENT}") == []
    for bucket in BUCKETS:
        assert world.files[bucket][OLD] == []
        assert world.files[bucket][RECENT] == ["x.jpg"]


def test_a_file_failure_skips_the_person_and_keeps_the_auth_user(client, world):
    """파일이 남은 채 auth 사용자를 지우면 그 파일을 가리킬 길이 없어진다 — 내일 다시 한다."""
    world.withdrawn(OLD, days_ago=31)
    world.fail = {"DELETE /storage/v1/object/profile-photos"}

    result = _run(client)

    assert result["deleted_accounts"] == 0
    assert result["skipped_accounts"] == 1
    assert world.calls("DELETE", f"/auth/v1/admin/users/{OLD}") == []
    assert OLD in world.emails


def test_a_failure_does_not_stop_the_next_person_in_line(client, world):
    """withdrawn_at 오름차순이라 맨 앞사람이 실패해도 뒷사람은 계속 지운다(권고 2)."""
    world.withdrawn(OLD, days_ago=40)
    world.withdrawn(RECENT, days_ago=35)
    world.fail = {f"DELETE /auth/v1/admin/users/{OLD}"}

    result = _run(client)

    assert result["deleted_accounts"] == 1
    assert result["skipped_accounts"] == 1
    assert len(world.calls("DELETE", f"/auth/v1/admin/users/{RECENT}")) == 1


def test_reports_go_one_year_after_they_were_made_not_after_they_were_resolved(client, world):
    world.reports = [
        {"id": "r-old", "created_at": NOW - timedelta(days=366), "resolved_at": None},
        {"id": "r-new", "created_at": NOW - timedelta(days=364), "resolved_at": NOW - timedelta(days=400)},
    ]

    result = _run(client)

    assert result["deleted_reports"] == 1
    assert [r["id"] for r in world.reports] == ["r-new"]
    assert "resolved_at" not in world.calls("DELETE", "/rest/v1/reports")[0].url.params


def test_expired_signup_blocks_go_but_infinity_stays(client, world):
    world.signup_blocks = [
        {"email_hmac": "a", "blocked_until": NOW - timedelta(days=1)},
        {"email_hmac": "b", "blocked_until": INFINITY},
        {"email_hmac": "c", "blocked_until": NOW + timedelta(days=1)},
    ]

    result = _run(client)

    assert result["deleted_signup_blocks"] == 1
    assert [b["email_hmac"] for b in world.signup_blocks] == ["b", "c"]


def test_running_again_finds_nothing_left(client, world):
    world.withdrawn(OLD, days_ago=31)
    world.reports = [{"id": "r-old", "created_at": NOW - timedelta(days=366), "resolved_at": None}]
    world.signup_blocks = [{"email_hmac": "a", "blocked_until": NOW - timedelta(days=1)}]
    _run(client)

    assert _run(client) == {
        "deleted_accounts": 0, "skipped_accounts": 0, "deleted_reports": 0,
        "deleted_signup_blocks": 0, "stale_key_rows": 0,
        "deleted_heart_proofs": 0,
    }


def test_rows_under_an_old_key_version_are_counted_and_warned(client, world, caplog):
    """키를 바꾼 뒤 옛 버전 지인 차단은 대조에서 빠진다 — 사람이 다시 등록하게 할지 볼 수 있게 센다(B4)."""
    world.contact_key_versions = [1, 1, 2]

    with caplog.at_level(logging.WARNING, logger="app.account.batch_router"):
        result = _run(client)

    assert result["stale_key_rows"] == 1
    assert "stale" in caplog.text


def test_the_batch_needs_the_scheduler(client, world, caplog):
    assert client.post("/batch/cleanup").status_code == 401
    assert client.post("/batch/cleanup", headers={"X-Batch-Secret": "wrong"}).status_code == 401
    assert world.requests == []

    with caplog.at_level(logging.WARNING, logger="app.account.batch_router"):
        _run(client)
    # 다른 배치와 같은 한 줄(DEPLOY.md §4-3 전환 확인용).
    assert "batch /batch/cleanup auth=secret" in caplog.text
