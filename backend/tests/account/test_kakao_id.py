"""`GET /account/kakao-id`(B5, 16e-1 전용). 앱은 profile_private 를 직접 읽지 못한다(ERD §11-20)."""
from account_world import AUTH, ME


def test_my_kakao_id_comes_back(client, world):
    world.kakao_ids[ME] = "fox_rain"

    response = client.get("/account/kakao-id", headers=AUTH)

    assert response.status_code == 200
    assert response.json() == {"kakao_id": "fox_rain"}


def test_no_kakao_id_is_null(client, world):
    assert client.get("/account/kakao-id", headers=AUTH).json() == {"kakao_id": None}


def test_my_kakao_id_is_read_only_through_the_decrypt_rpc(client, world):
    world.kakao_ids[ME] = "fox_enc"

    assert client.get("/account/kakao-id", headers=AUTH).json() == {"kakao_id": "fox_enc"}
    assert world.decrypt_bodies == [{"p_profile": ME, "p_key": "phone-key-test"}]
    assert not [r for r in world.requests if r.url.path == "/rest/v1/profile_private"]


def test_my_kakao_id_fails_when_decrypt_fails(client, world):
    """평문 열로 물러설 곳이 없다(M2) — "아이디 없음" 이 아니라 실패다."""
    world.kakao_ids[ME] = "fox_enc"
    world.fail.add("POST /rest/v1/rpc/decrypt_profile_private")

    response = client.get("/account/kakao-id", headers=AUTH)

    assert response.status_code == 500
    assert not [r for r in world.requests if r.url.path == "/rest/v1/profile_private"]
