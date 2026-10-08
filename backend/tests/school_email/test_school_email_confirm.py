"""`POST /school-email/confirm` — 앱이 verifyOTP(emailChange) 성공 **뒤** 부르는 두 번째 검사.

소셜 계정은 가입하는 순간 email_confirmed_at 이 채워진다(카카오는 이메일이 없는데도). 그래서 인증 증거는
① 계정에 provider `email` 인 identity 가 붙어 있고 ② 계정 이메일의 도메인이 등록된 학교 도메인인 것, 둘이다.
"""
import json
from datetime import datetime

import pytest

from app.core import errors
from app.signup_policy import bytea_literal, hash_email
from school_email_world import AUTH, IDENTITY_KEY, ME, NOW, OTHER, SNU


def _confirm(client):
    return client.post("/school-email/confirm", headers=AUTH)


def _patches(world):
    return world.calls("PATCH", "/rest/v1/profiles")


def test_after_verify_otp_the_school_and_time_are_recorded(client, world):
    world.verified_school_email("hong@snu.ac.kr")

    response = _confirm(client)

    assert response.status_code == 200
    assert response.json() == {"ok": True}
    [patch] = _patches(world)
    # 조건을 요청 자체에 건다 — 동시에 두 번 불려도 처음 기록이 남는다.
    assert dict(patch.url.params) == {"id": f"eq.{ME}", "school_email_verified_at": "is.null"}
    body = json.loads(patch.content)
    assert body["university_id"] == SNU
    assert datetime.fromisoformat(body["school_email_verified_at"]) == NOW


def test_it_reads_the_callers_own_auth_user(client, world):
    world.verified_school_email("hong@snu.ac.kr")

    _confirm(client)

    reads = world.calls("GET", "/auth/v1/user")
    assert reads and all(r.headers["authorization"] == AUTH["Authorization"] for r in reads)


def test_a_social_account_whose_email_is_merely_confirmed_is_403(client, world):
    """email_confirmed_at 은 소셜 가입 순간 채워진다 — 그것으로 판단하면 안 된다."""
    assert world.auth_user["email_confirmed_at"]

    response = _confirm(client)

    assert response.status_code == 403
    assert response.json()["detail"] == errors.SCHOOL_EMAIL_NOT_VERIFIED == "학교 메일 인증이 끝나지 않았어요"
    assert _patches(world) == []


def test_a_school_address_without_an_email_identity_is_403(client, world):
    """앱을 거치지 않고 이메일 칸만 학교 주소로 바뀐 계정(구글 가입 + 학교 도메인 구글 메일 등)."""
    world.auth_user.update(email="hong@snu.ac.kr", email_confirmed_at="2026-10-01T00:00:00Z",
                           identities=[{"provider": "google", "identity_data": {"email": "hong@snu.ac.kr"}}])

    response = _confirm(client)

    assert response.status_code == 403
    assert response.json()["detail"] == errors.SCHOOL_EMAIL_NOT_VERIFIED
    assert _patches(world) == []


def test_an_email_identity_with_an_empty_email_is_403(client, world):
    world.verified_school_email("hong@snu.ac.kr")
    world.auth_user["email"] = ""

    assert _confirm(client).status_code == 403
    assert _patches(world) == []


def test_a_google_mail_account_is_stopped_by_the_domain_check(client, world):
    """구글 계정은 가입 때 구글 메일이 이메일 칸에 들어 있다 — 도메인 검사가 걸러낸다."""
    world.verified_school_email("hong@gmail.com")

    response = _confirm(client)

    assert response.status_code == 422
    assert response.json()["detail"] == errors.SCHOOL_EMAIL_UNKNOWN_DOMAIN
    assert _patches(world) == []


def test_a_blocked_email_is_422_again_here(client, world):
    world.verified_school_email("hong@snu.ac.kr")
    world.blocked_hmacs.add(bytea_literal(hash_email(IDENTITY_KEY, "hong@snu.ac.kr")))

    response = _confirm(client)

    assert response.status_code == 422
    assert response.json()["detail"] == errors.SCHOOL_EMAIL_BLOCKED
    assert _patches(world) == []


def test_an_email_used_by_another_account_is_409_again_here(client, world):
    world.verified_school_email("hong@snu.ac.kr")
    world.accounts["hong@snu.ac.kr"] = (OTHER, "apple")

    response = _confirm(client)

    assert response.status_code == 409
    assert response.json()["provider"] == "apple"
    assert _patches(world) == []


def test_the_account_email_is_lowercased_before_the_checks(client, world):
    world.verified_school_email("Hong@SNU.ac.kr")

    assert _confirm(client).status_code == 200
    assert world.provider_lookups == [{"p_email": "hong@snu.ac.kr", "p_caller": ME}]


def test_calling_again_leaves_the_first_record_alone(client, world):
    world.verified_school_email("hong@snu.ac.kr")
    _confirm(client)
    first = dict(world.profile)

    again = _confirm(client)

    assert again.status_code == 200
    assert again.json() == {"ok": True}
    assert world.profile == first
    assert len(_patches(world)) == 1


def test_an_already_recorded_profile_is_not_touched(client, world):
    world.verified_school_email("hong@snu.ac.kr")
    world.profile.update(university_id=SNU, school_email_verified_at="2026-10-02T00:00:00+00:00")

    assert _confirm(client).status_code == 200
    assert _patches(world) == []
    assert world.profile["school_email_verified_at"] == "2026-10-02T00:00:00+00:00"


@pytest.mark.parametrize("status_code, setup", [
    (403, lambda w: w.profile.update(status="suspended")),
    (403, lambda w: setattr(w, "consented", False)),
    (401, lambda w: w.profile.update(status="withdrawn")),
])
def test_the_same_gates_as_check(client, world, status_code, setup):
    world.verified_school_email("hong@snu.ac.kr")
    setup(world)

    assert _confirm(client).status_code == status_code
    assert _patches(world) == []


def test_suspension_comes_before_the_unfinished_check(client, world):
    world.profile["status"] = "suspended"

    response = _confirm(client)

    assert response.headers["X-Account-Status"] == "suspended"
