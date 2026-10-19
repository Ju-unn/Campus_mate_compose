import json

from applicant_world import AUTH, PROFILE, TABLE, request_row

URL = "/me/verification-method"


def _put(client, method, **kwargs):
    return client.put(URL, json={"method": method}, headers=AUTH, **kwargs)


def test_put_method_requires_login(client, world):
    assert client.put(URL, json={"method": None}).status_code == 401


def test_put_method_requires_login_consent_and_not_suspended(client, world):
    world.profile["status"] = "suspended"
    suspended = _put(client, "graduate_certificate")
    assert suspended.status_code == 403
    assert suspended.headers["X-Account-Status"] == "suspended"

    world.profile["status"] = "active"
    world.consented = False
    assert _put(client, "graduate_certificate").status_code == 403
    assert "X-Account-Status" not in _put(client, "graduate_certificate").headers

    world.profile["status"] = "withdrawn"
    assert _put(client, "graduate_certificate").status_code == 401
    assert world.calls("PATCH", "/profiles") == []


def test_put_method_sets_and_clears_value(client, world):
    for method in ("school_email", "graduate_certificate", None):
        response = _put(client, method)

        assert response.status_code == 200
        assert response.json() == {"verification_method": method, "cancelled_request": False}
        assert world.profile["verification_method"] == method
        assert json.loads(world.calls("PATCH", "/profiles")[-1].content) == {"verification_method": method}


def test_put_method_rejects_unknown_values(client, world):
    assert _put(client, "naver").status_code == 422
    assert client.put(URL, json={}, headers=AUTH).status_code == 422
    assert world.calls("PATCH", "/profiles") == []


def test_put_method_rejects_verified_person(client, world):
    world.profile["school_email_verified_at"] = "2026-10-01T00:00:00+00:00"

    response = _put(client, "school_email")

    assert response.status_code == 409
    assert response.json()["code"] == "already_verified"
    assert world.calls("PATCH", "/profiles") == []


def test_put_graduate_when_flag_off_is_403(client, world, monkeypatch):
    monkeypatch.delenv("GRADUATE_VERIFICATION_ENABLED")
    world.profile["verification_method"] = None

    blocked = _put(client, "graduate_certificate")

    assert blocked.status_code == 403
    assert blocked.json()["code"] == "graduate_disabled"
    assert world.calls("PATCH", "/profiles") == []
    # 끄기 · 학교 메일 · 비우기는 플래그와 상관없이 된다 — 새 앱이 꺼진 서버에서도 02 로 돌아갈 수 있다.
    assert _put(client, "school_email").status_code == 200
    assert _put(client, None).status_code == 200


def test_switching_away_cancels_pending_request_and_deletes_photo(client, world):
    path = f"{PROFILE}/r1.jpg"
    world.rows.append(request_row("pending", rid="r1", photo_path=path))
    world.objects[path] = b"photo"

    response = _put(client, None)

    assert response.status_code == 200
    assert response.json() == {"verification_method": None, "cancelled_request": True}
    row = world.rows[0]
    assert (row["status"], row["reason"]) == ("cancelled", "switched")
    assert row["ocr_document_number"] is None and row["previous_school_email"] is None
    assert world.objects == {}
    assert row["photo_path"] is None
    # 취소가 먼저, 프로필 값 쓰기가 그 다음 — 취소가 실패하면 프로필은 그대로라 다시 눌러도 같다. 사진 지우기는 맨 뒤(실패해도 결과 그대로).
    writes = [(r.method, r.url.path.rsplit("/", 1)[-1]) for r in world.requests if r.method in ("PATCH", "DELETE")]
    assert writes == [("PATCH", "graduate_verification_requests"), ("PATCH", "profiles"),
                      ("DELETE", "r1.jpg"), ("PATCH", "graduate_verification_requests")]


def test_choosing_graduate_again_keeps_the_pending_request(client, world):
    world.rows.append(request_row("pending", rid="r1", photo_path=f"{PROFILE}/r1.jpg"))

    response = _put(client, "graduate_certificate")

    assert response.json()["cancelled_request"] is False
    assert world.rows[0]["status"] == "pending"
    assert world.calls("PATCH", "graduate_verification_requests") == []


def test_switching_away_survives_a_failed_photo_delete(client, world):
    path = f"{PROFILE}/r1.jpg"
    world.rows.append(request_row("pending", rid="r1", photo_path=path))
    world.objects[path] = b"photo"
    world.fail_delete = True

    response = _put(client, "school_email")

    assert response.status_code == 200
    assert response.json()["cancelled_request"] is True
    assert world.rows[0]["status"] == "cancelled"
    # 경로를 남겨 매시 배치가 다시 지우게 한다.
    assert world.rows[0]["photo_path"] == path
    assert world.profile["verification_method"] == "school_email"


def test_put_method_logs_ids_only(client, world, caplog):
    path = f"{PROFILE}/r1.jpg"
    world.rows.append(request_row("pending", rid="r1", photo_path=path))
    world.fail_delete = True

    with caplog.at_level("DEBUG"):
        _put(client, None)

    assert path not in caplog.text
    assert TABLE not in caplog.text
