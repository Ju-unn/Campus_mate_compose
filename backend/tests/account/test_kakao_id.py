"""`GET /account/kakao-id`(B5, 16e-1 전용). 앱은 profile_private 를 직접 읽지 못한다(ERD §11-20)."""
from account_world import AUTH, ME


def test_my_kakao_id_comes_back(client, world):
    world.kakao_ids[ME] = "fox_rain"

    response = client.get("/account/kakao-id", headers=AUTH)

    assert response.status_code == 200
    assert response.json() == {"kakao_id": "fox_rain"}


def test_no_kakao_id_is_null(client, world):
    assert client.get("/account/kakao-id", headers=AUTH).json() == {"kakao_id": None}
