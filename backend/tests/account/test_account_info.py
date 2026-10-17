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


def test_missing_private_values_are_null_not_500(client, world):
    response = client.get("/account", headers=AUTH)

    assert response.status_code == 200
    assert response.json()["real_name"] is None
    assert response.json()["kakao_id"] is None


def test_a_pending_student_id_caller_gets_the_account(client, world):
    # 학생증 제거(10-17): 학교 메일 + 학과면 들어온다.
    world.profiles[ME]["student_verification"] = "pending"

    assert client.get("/account", headers=AUTH).status_code == 200


def test_a_caller_without_a_department_is_403(client, world):
    world.profiles[ME]["department"] = None

    assert client.get("/account", headers=AUTH).status_code == 403


def test_real_name_never_reaches_logs(client, world, caplog):
    world.real_names[ME] = "홍길동"

    with caplog.at_level(logging.DEBUG):
        response = client.get("/account", headers=AUTH)

    assert response.status_code == 200
    assert "홍길동" not in caplog.text


# 실명 · 카톡 아이디는 암호문 열을 복호화해서만 읽는다(M2 — 평문 열은 없다).
def test_account_reads_the_private_values_only_through_the_decrypt_rpc(client, world):
    world.real_names[ME] = "홍길동"
    world.kakao_ids[ME] = "fox_enc"

    body = client.get("/account", headers=AUTH).json()

    assert body["real_name"] == "홍길동" and body["kakao_id"] == "fox_enc"
    # 키는 JSON 바디로만 간다.
    assert world.decrypt_bodies == [{"p_profile": ME, "p_key": "phone-key-test"}]
    assert all("phone-key-test" not in str(r.url) for r in world.requests)
    assert not [r for r in world.requests if r.url.path == "/rest/v1/profile_private"]


def test_account_fails_instead_of_showing_blanks_when_decrypt_fails(client, world, caplog):
    """복호화가 안 될 때 빈칸으로 보여 주면 "실명 미입력" 으로 오인한다 — 요청을 실패시킨다. 로그에 값 · 키는 없다."""
    world.real_names[ME] = "홍길동"
    world.kakao_ids[ME] = "fox_enc"
    world.fail.add("POST /rest/v1/rpc/decrypt_profile_private")

    with caplog.at_level(logging.DEBUG):
        response = client.get("/account", headers=AUTH)

    assert response.status_code == 500
    assert not [r for r in world.requests if r.url.path == "/rest/v1/profile_private"]
    for secret in ("홍길동", "fox_enc", "phone-key-test"):
        assert secret not in caplog.text and secret not in response.text
