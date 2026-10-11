"""`GET /account/kakao-id`(B5, 16e-1 전용). 앱은 profile_private 를 직접 읽지 못한다(ERD §11-20)."""
from account_world import AUTH, ME


def test_my_kakao_id_comes_back(client, world):
    world.kakao_ids[ME] = "fox_rain"

    response = client.get("/account/kakao-id", headers=AUTH)

    assert response.status_code == 200
    assert response.json() == {"kakao_id": "fox_rain"}


def test_no_kakao_id_is_null(client, world):
    assert client.get("/account/kakao-id", headers=AUTH).json() == {"kakao_id": None}


def test_my_kakao_id_is_read_from_the_encrypted_column_first(client, world):
    world.kakao_ids_enc[ME] = "fox_enc"
    world.kakao_ids[ME] = "fox_old"

    assert client.get("/account/kakao-id", headers=AUTH).json() == {"kakao_id": "fox_enc"}
    assert world.decrypt_bodies == [{"p_profile": ME, "p_key": "phone-key-test"}]


def test_my_kakao_id_falls_back_to_the_plain_column_when_decrypt_fails(client, world):
    world.fail.add("POST /rest/v1/rpc/decrypt_profile_private")
    world.kakao_ids[ME] = "fox_old"

    assert client.get("/account/kakao-id", headers=AUTH).json() == {"kakao_id": "fox_old"}
