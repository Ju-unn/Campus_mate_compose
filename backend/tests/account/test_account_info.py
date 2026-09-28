"""`GET /account`(16e 계정 화면). 실명은 본인에게 가는 이 응답에만 있고 로그에는 없다."""
import logging

from account_world import AUTH, ME


def test_my_account_rows_come_back(client, world):
    world.real_names[ME] = "홍길동"
    world.kakao_ids[ME] = "fox_rain"

    response = client.get("/account", headers=AUTH)

    assert response.status_code == 200
    assert response.json() == {
        "real_name": "홍길동", "birth_year": 2003, "university": "서울대학교",
        "joined_at": "2026-09-01T10:00:00+00:00", "kakao_id": "fox_rain",
    }


def test_missing_private_row_is_null_not_500(client, world):
    body = client.get("/account", headers=AUTH).json()

    assert body["real_name"] is None
    assert body["kakao_id"] is None


def test_unverified_caller_is_403(client, world):
    world.profiles[ME]["student_verification"] = "pending"

    assert client.get("/account", headers=AUTH).status_code == 403


def test_real_name_never_reaches_logs(client, world, caplog):
    world.real_names[ME] = "홍길동"

    with caplog.at_level(logging.DEBUG):
        response = client.get("/account", headers=AUTH)

    assert response.status_code == 200
    assert "홍길동" not in caplog.text
