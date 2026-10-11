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


# 실명 · 카톡 아이디는 enc 열을 복호화해 읽고, 비었거나 복호화가 안 되면 옛 평문 열로 폴백한다(서버 PR 2).
def test_account_reads_the_decrypted_values_when_enc_columns_are_filled(client, world):
    world.real_names_enc[ME] = "홍길동"
    world.kakao_ids_enc[ME] = "fox_enc"
    world.real_names[ME] = "옛이름"
    world.kakao_ids[ME] = "fox_old"

    body = client.get("/account", headers=AUTH).json()

    assert body["real_name"] == "홍길동" and body["kakao_id"] == "fox_enc"
    # 키는 JSON 바디로만 간다.
    assert world.decrypt_bodies == [{"p_profile": ME, "p_key": "phone-key-test"}]
    assert all("phone-key-test" not in str(r.url) for r in world.requests)


def test_account_falls_back_per_field_to_the_plain_column_when_enc_is_null(client, world):
    world.real_names_enc[ME] = "홍길동"      # 실명만 enc, 카톡 아이디는 아직 평문뿐
    world.kakao_ids[ME] = "fox_old"

    body = client.get("/account", headers=AUTH).json()

    assert body["real_name"] == "홍길동" and body["kakao_id"] == "fox_old"


def test_account_falls_back_to_the_plain_columns_when_decrypt_is_unavailable(client, world):
    """서버가 DB 보다 먼저 나가 RPC 가 404 여도 계정 화면은 그대로 뜬다(배포 순서)."""
    world.fail.add("POST /rest/v1/rpc/decrypt_profile_private")
    world.real_names[ME] = "홍길동"
    world.kakao_ids[ME] = "fox_old"

    response = client.get("/account", headers=AUTH)

    assert response.status_code == 200
    assert response.json()["real_name"] == "홍길동" and response.json()["kakao_id"] == "fox_old"


def test_account_is_null_when_decrypt_fails_and_the_plain_columns_are_empty(client, world):
    world.fail.add("POST /rest/v1/rpc/decrypt_profile_private")

    body = client.get("/account", headers=AUTH).json()

    assert body["real_name"] is None and body["kakao_id"] is None


def test_decrypt_failure_and_decrypted_values_never_reach_logs(client, world, caplog):
    world.real_names_enc[ME] = "홍길동"
    world.kakao_ids_enc[ME] = "fox_enc"
    world.fail.add("POST /rest/v1/rpc/decrypt_profile_private")
    world.real_names[ME] = "홍길동"
    world.kakao_ids[ME] = "fox_old"

    with caplog.at_level(logging.DEBUG):
        client.get("/account", headers=AUTH)

    assert "복호화" in caplog.text   # 폴백했다는 흔적은 남는다
    for secret in ("홍길동", "fox_old", "fox_enc", "phone-key-test"):
        assert secret not in caplog.text
