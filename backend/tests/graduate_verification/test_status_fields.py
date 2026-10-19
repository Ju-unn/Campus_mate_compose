from applicant_world import AUTH, TABLE, request_row, ApplicantWorld


def _status(client, world: ApplicantWorld) -> dict:
    response = client.get("/me/verification-status", headers=AUTH)
    assert response.status_code == 200
    return response.json()


def test_old_client_fields_unchanged(client, world, monkeypatch):
    # 플래그 꺼짐 + 방법 미선택 = 지금 동작. 옛 앱이 읽는 다섯 칸은 값 · 이름이 그대로다.
    monkeypatch.delenv("GRADUATE_VERIFICATION_ENABLED")
    world.profile["verification_method"] = None

    body = _status(client, world)

    assert body["status"] == "verified"
    assert body["reject_reason"] is None
    assert body["school_email_verified"] is False
    assert body["has_school_info"] is False
    assert body["consent"] == "current"
    assert body["graduate_enabled"] is False
    assert body["verification_method"] is None
    assert body["graduate"] is None


def test_old_client_fields_for_a_verified_person(client, world):
    world.profile.update(school_email_verified_at="2026-10-01T00:00:00+00:00", department="컴퓨터공학")

    body = _status(client, world)

    assert (body["status"], body["school_email_verified"], body["has_school_info"]) == ("verified", True, True)
    assert body["graduate_enabled"] is True


def test_status_reads_graduate_state_only_for_graduate_method_unverified(client, world):
    world.profile["verification_method"] = "school_email"
    _status(client, world)
    assert world.touched(TABLE) == []

    world.profile.update(verification_method="graduate_certificate", school_email_verified_at="2026-10-01T00:00:00+00:00")
    _status(client, world)
    assert world.touched(TABLE) == []

    world.profile.update(school_email_verified_at=None)
    _status(client, world)
    assert len(world.touched(TABLE)) == 1


def test_status_does_not_read_graduate_state_when_flag_is_off(client, world, monkeypatch):
    monkeypatch.delenv("GRADUATE_VERIFICATION_ENABLED")

    body = _status(client, world)

    assert world.touched(TABLE) == []
    assert body["graduate_enabled"] is False and body["graduate"] is None
    assert body["verification_method"] == "graduate_certificate"


def test_status_graduate_pending_shape(client, world):
    world.rows.append(request_row("pending", created_at="2026-10-24T01:00:00+00:00"))

    body = _status(client, world)

    assert body["verification_method"] == "graduate_certificate"
    assert body["graduate"] == {
        "state": "pending", "reject_reason": None, "attempts_left": 2, "submitted_at": "2026-10-24T01:00:00+00:00"}


def test_status_graduate_rejected_shape_counts_attempts(client, world):
    world.rows += [
        request_row("rejected", "unverifiable", rid="old", created_at="2026-10-20T00:00:00+00:00"),
        request_row("rejected", "unreadable", rid="new", created_at="2026-10-22T00:00:00+00:00"),
    ]

    body = _status(client, world)

    assert body["graduate"]["state"] == "rejected"
    assert body["graduate"]["reject_reason"] == "unreadable"
    assert body["graduate"]["attempts_left"] == 1


def test_status_has_no_graduate_object_when_latest_is_cancelled(client, world):
    # 방법을 바꿨다 돌아온 사람 — 폼으로 간다(app: method=graduate_certificate, graduate=null).
    world.rows.append(request_row("cancelled", "switched"))

    body = _status(client, world)

    assert body["graduate"] is None


def test_expired_requests_do_not_use_up_attempts(client, world):
    world.rows += [
        request_row("cancelled", "expired", rid="a", created_at="2026-09-01T00:00:00+00:00"),
        request_row("cancelled", "expired", rid="b", created_at="2026-09-20T00:00:00+00:00"),
        request_row("rejected", "unreadable", rid="c", created_at="2026-10-20T00:00:00+00:00"),
    ]

    assert _status(client, world)["graduate"]["attempts_left"] == 2
