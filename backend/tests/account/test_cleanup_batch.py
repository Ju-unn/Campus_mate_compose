"""정리 배치 `POST /batch/cleanup`(B3 · B4). 매일 04:00 Asia/Seoul, 처음부터 OIDC 로 부른다(DEPLOY.md)."""
import logging
from datetime import timedelta

from account_world import BUCKETS, INFINITY, NOW, OLD, RECENT

# conftest 가 구글 서명 확인을 가짜로 통과시킨다.
SCHEDULER_TOKEN = {"Authorization": "Bearer id-token"}


def _run(client) -> dict:
    response = client.post("/batch/cleanup", headers=SCHEDULER_TOKEN)
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


def test_reports_go_one_year_after_they_were_resolved_and_open_ones_stay(client, world):
    """ERD_DECISIONS §11-23: 처리(조치 · 기각)가 끝나고 1년 뒤 지운다. 열린 신고는 몇 년이 지나도 남는다."""
    world.reports = [
        {"id": "r-open", "created_at": NOW - timedelta(days=800), "resolved_at": None},
        {"id": "r-resolved-old", "created_at": NOW - timedelta(days=500), "resolved_at": NOW - timedelta(days=366)},
        {"id": "r-resolved-new", "created_at": NOW - timedelta(days=500), "resolved_at": NOW - timedelta(days=364)},
    ]

    result = _run(client)

    assert result["deleted_reports"] == 1
    assert [r["id"] for r in world.reports] == ["r-open", "r-resolved-new"]
    assert "created_at" not in world.calls("DELETE", "/rest/v1/reports")[0].url.params


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
    world.reports = [
        {"id": "r-old", "created_at": NOW - timedelta(days=400), "resolved_at": NOW - timedelta(days=366)},
    ]
    world.signup_blocks = [{"email_hmac": "a", "blocked_until": NOW - timedelta(days=1)}]
    _run(client)

    assert _run(client) == {
        "deleted_accounts": 0, "skipped_accounts": 0, "deleted_reports": 0,
        "deleted_signup_blocks": 0, "stale_key_rows": 0,
        "deleted_heart_proofs": 0, "deleted_unverified": 0, "deleted_temp_email_accounts": 0,
    }


# 학교 메일 확인 전 계정 14일 뒤 삭제(소셜 로그인 전환) -------------------------------------------

UNVERIFIED_OLD = "55555555-5555-5555-5555-555555555555"     # 15일 전 가입, 학교 메일 전
UNVERIFIED_NEW = "66666666-6666-6666-6666-666666666666"     # 13일 전 가입, 학교 메일 전


def test_an_account_still_unverified_after_14_days_goes_but_13_days_stays(client, world):
    world.unverified(UNVERIFIED_OLD, days_ago=15)
    world.unverified(UNVERIFIED_NEW, days_ago=13)

    result = _run(client)

    assert result["deleted_unverified"] == 1
    assert world.unverified_lookups == [{"p_older_than_days": 14, "p_limit": 100}]
    # 탈퇴 30일 정리와 같은 길 — 버킷 넷의 파일을 먼저 지우고 auth 사용자째 지운다(profiles 는 cascade).
    assert len(world.calls("DELETE", f"/auth/v1/admin/users/{UNVERIFIED_OLD}")) == 1
    assert world.calls("DELETE", f"/auth/v1/admin/users/{UNVERIFIED_NEW}") == []
    for bucket in BUCKETS:
        assert world.files[bucket][UNVERIFIED_OLD] == []
        assert world.files[bucket][UNVERIFIED_NEW] == ["u.jpg"]


def test_a_verified_or_withdrawn_account_is_not_counted_as_unverified(client, world):
    world.withdrawn(OLD, days_ago=31)

    result = _run(client)

    assert result["deleted_accounts"] == 1
    assert result["deleted_unverified"] == 0
    assert world.calls("DELETE", "/auth/v1/admin/users/11111111-1111-1111-1111-111111111111") == []


def test_one_unverified_failure_does_not_stop_the_next(client, world):
    world.unverified(UNVERIFIED_OLD, days_ago=20)
    world.unverified(UNVERIFIED_NEW, days_ago=16)
    world.fail = {f"DELETE /auth/v1/admin/users/{UNVERIFIED_OLD}"}

    result = _run(client)

    assert result["deleted_unverified"] == 1
    assert result["skipped_accounts"] == 1
    assert len(world.calls("DELETE", f"/auth/v1/admin/users/{UNVERIFIED_NEW}")) == 1
    assert UNVERIFIED_OLD in world.emails


def test_a_file_failure_keeps_the_unverified_auth_user_for_tomorrow(client, world):
    world.unverified(UNVERIFIED_OLD, days_ago=15)
    world.fail = {"DELETE /storage/v1/object/avatars"}

    result = _run(client)

    assert result["deleted_unverified"] == 0
    assert world.calls("DELETE", f"/auth/v1/admin/users/{UNVERIFIED_OLD}") == []


def test_running_the_unverified_step_twice_is_safe(client, world):
    world.unverified(UNVERIFIED_OLD, days_ago=15)
    assert _run(client)["deleted_unverified"] == 1

    again = _run(client)

    assert again["deleted_unverified"] == 0
    assert again["skipped_accounts"] == 0
    assert len(world.calls("DELETE", f"/auth/v1/admin/users/{UNVERIFIED_OLD}")) == 1


def test_an_account_verified_since_the_lookup_is_skipped_not_deleted(client, world):
    """RPC 가 고른 뒤 그 사이 인증을 마쳤으면 지우지 않는다 — 지우기 직전에 프로필을 다시 읽는다."""
    world.unverified(UNVERIFIED_OLD, days_ago=15)
    world.profiles[UNVERIFIED_OLD]["school_email_verified_at"] = "2026-09-27T03:59:00+00:00"
    world.stale_unverified = [UNVERIFIED_OLD]

    result = _run(client)

    assert result["deleted_unverified"] == 0
    assert result["skipped_accounts"] == 1
    assert world.calls("DELETE", f"/auth/v1/admin/users/{UNVERIFIED_OLD}") == []
    assert world.files["avatars"][UNVERIFIED_OLD] == ["u.jpg"]


def test_an_unreadable_profile_is_skipped_not_deleted(client, world):
    """확인할 수 없으면 지우지 않는 쪽이다. 다음 사람은 계속 지운다."""
    world.unverified(UNVERIFIED_OLD, days_ago=20)
    world.unverified(UNVERIFIED_NEW, days_ago=16)
    world.unreadable_profiles = {UNVERIFIED_OLD}

    result = _run(client)

    assert result["deleted_unverified"] == 1
    assert result["skipped_accounts"] == 1
    assert world.calls("DELETE", f"/auth/v1/admin/users/{UNVERIFIED_OLD}") == []
    assert len(world.calls("DELETE", f"/auth/v1/admin/users/{UNVERIFIED_NEW}")) == 1


def test_a_profile_gone_since_the_lookup_is_skipped(client, world):
    world.stale_unverified = [UNVERIFIED_OLD]  # 프로필 행이 없다

    result = _run(client)

    assert result["deleted_unverified"] == 0
    assert result["skipped_accounts"] == 1


def test_the_python_side_still_caps_the_unverified_batch_at_100(client, world):
    for n in range(105):
        world.unverified(f"{n:08d}-0000-0000-0000-000000000000", days_ago=15)
    world.stale_unverified = [f"{n:08d}-0000-0000-0000-000000000000" for n in range(105)]

    result = _run(client)

    assert result["deleted_unverified"] == 100


# 임시 이메일 계정 잔여물(학교 메일 verify 가 못 지운 것) — 24시간 뒤 지운다 -----------------------------------

TEMP_OLD = "77777777-7777-7777-7777-777777777777"
TEMP_NEW = "88888888-8888-8888-8888-888888888888"
OLD_EMAIL_USER = "99999999-9999-9999-9999-999999999999"


def test_a_leftover_temp_email_account_goes_after_24_hours(client, world):
    world.temp_email_account(TEMP_OLD, hours_ago=25)

    result = _run(client)

    assert result["deleted_temp_email_accounts"] == 1
    assert len(world.calls("DELETE", f"/auth/v1/admin/users/{TEMP_OLD}")) == 1
    # 지우기 직전에 프로필이 정말 없는지 다시 읽는다.
    rechecks = [r for r in world.calls("GET", "/rest/v1/profiles") if r.url.params.get("id") == f"eq.{TEMP_OLD}"]
    assert rechecks


def test_a_temp_account_within_24_hours_stays(client, world):
    world.temp_email_account(TEMP_NEW, hours_ago=23)

    assert _run(client)["deleted_temp_email_accounts"] == 0
    assert world.calls("DELETE", f"/auth/v1/admin/users/{TEMP_NEW}") == []


def test_an_email_account_with_a_profile_stays(client, world):
    """소셜 전환 전 학교 메일 OTP 로 가입한 옛 계정은 provider 가 email 뿐이어도 프로필이 있다."""
    world.temp_email_account(OLD_EMAIL_USER, hours_ago=24 * 40, with_profile=True)

    assert _run(client)["deleted_temp_email_accounts"] == 0
    assert world.calls("DELETE", f"/auth/v1/admin/users/{OLD_EMAIL_USER}") == []


def test_a_social_account_without_a_profile_is_not_a_temp_account(client, world):
    world.auth_users[TEMP_OLD] = {"id": TEMP_OLD, "created_at": "2026-09-01T00:00:00Z",
                                  "identities": [{"provider": "kakao"}], "app_metadata": {"provider": "kakao"}}
    world.emails[TEMP_OLD] = ""

    assert _run(client)["deleted_temp_email_accounts"] == 0
    assert world.calls("DELETE", f"/auth/v1/admin/users/{TEMP_OLD}") == []


def test_an_email_plus_social_account_is_not_a_temp_account(client, world):
    world.temp_email_account(TEMP_OLD, hours_ago=48)
    world.auth_users[TEMP_OLD]["identities"].append({"provider": "kakao"})

    assert _run(client)["deleted_temp_email_accounts"] == 0


def test_an_unreadable_profile_keeps_the_temp_account(client, world):
    world.temp_email_account(TEMP_OLD, hours_ago=48)
    world.unreadable_profiles = {TEMP_OLD}

    assert _run(client)["deleted_temp_email_accounts"] == 0
    assert world.calls("DELETE", f"/auth/v1/admin/users/{TEMP_OLD}") == []


def test_the_admin_list_is_read_page_by_page(client, world):
    for n in range(130):
        world.temp_email_account(f"{n:08d}-1111-1111-1111-111111111111", hours_ago=30)

    result = _run(client)

    # 최대 p_limit(100) 개만 지운다. 목록은 여러 쪽에 걸쳐 읽는다.
    assert result["deleted_temp_email_accounts"] == 100
    assert len({r.url.params["page"] for r in world.admin_list_requests}) >= 2


def test_a_failing_admin_list_does_not_stop_the_other_steps(client, world):
    world.admin_list_status = 500
    world.unverified(UNVERIFIED_OLD, days_ago=15)
    world.withdrawn(OLD, days_ago=31)

    result = _run(client)

    assert result["deleted_temp_email_accounts"] == 0
    assert result["deleted_unverified"] == 1
    assert result["deleted_accounts"] == 1


def test_a_temp_candidate_skipped_for_its_profile_is_counted(client, world):
    """프로필이 있어 건너뛴 이메일 계정을 skipped_accounts 에 센다(운영에서 보이게, 지시문 12-3)."""
    world.temp_email_account(OLD_EMAIL_USER, hours_ago=24 * 40, with_profile=True)

    result = _run(client)

    assert result["deleted_temp_email_accounts"] == 0
    assert result["skipped_accounts"] == 1


def test_a_temp_candidate_skipped_for_an_unreadable_profile_is_counted(client, world):
    world.temp_email_account(TEMP_OLD, hours_ago=48)
    world.unreadable_profiles = {TEMP_OLD}

    result = _run(client)

    assert result["deleted_temp_email_accounts"] == 0
    assert result["skipped_accounts"] == 1


def test_old_email_accounts_with_profiles_do_not_crowd_out_a_leftover(client, world):
    """프로필 있는 옛 이메일 계정이 100개를 넘어도 그 뒤의 진짜 잔여물을 지운다(후보 100개 자르기에 막히지 않는다)."""
    for n in range(120):
        world.temp_email_account(f"{n:08d}-2222-2222-2222-222222222222", hours_ago=24 * 40, with_profile=True)
    world.temp_email_account(TEMP_OLD, hours_ago=25)

    result = _run(client)

    assert result["deleted_temp_email_accounts"] == 1
    assert len(world.calls("DELETE", f"/auth/v1/admin/users/{TEMP_OLD}")) == 1
    assert result["skipped_accounts"] == 120


def test_running_the_temp_step_twice_is_safe(client, world):
    world.temp_email_account(TEMP_OLD, hours_ago=25)
    assert _run(client)["deleted_temp_email_accounts"] == 1

    assert _run(client)["deleted_temp_email_accounts"] == 0
    assert len(world.calls("DELETE", f"/auth/v1/admin/users/{TEMP_OLD}")) == 1


def test_rows_under_an_old_key_version_are_counted_and_warned(client, world, caplog):
    """키를 바꾼 뒤 옛 버전 지인 차단은 대조에서 빠진다 — 사람이 다시 등록하게 할지 볼 수 있게 센다(B4)."""
    world.contact_key_versions = [1, 1, 2]

    with caplog.at_level(logging.WARNING, logger="app.account.batch_router"):
        result = _run(client)

    assert result["stale_key_rows"] == 1
    assert "stale" in caplog.text


def test_the_batch_needs_the_scheduler(client, world):
    # 옛 공유 열쇠 헤더는 이제 문이 아니다(OIDC 전환 5단계).
    assert client.post("/batch/cleanup").status_code == 401
    assert client.post("/batch/cleanup", headers={"X-Batch-Secret": "right"}).status_code == 401
    assert world.requests == []

    _run(client)
