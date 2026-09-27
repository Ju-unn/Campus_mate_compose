"""정지된 사람은 모든 인증 API 에서 403 + X-Account-Status 헤더를 받는다(계획서 B7, Ruling 8)."""
from fake_supabase import AUTH, PARTNER


def test_a_suspended_caller_gets_403_and_the_header(client, world):
    world.my_status = "suspended"

    for response in (client.get("/blocks", headers=AUTH),
                     client.get(f"/profiles/{PARTNER}", headers=AUTH),
                     client.get("/cards/today", headers=AUTH)):
        assert response.status_code == 403
        assert response.json()["detail"] == "이용이 제한된 계정이에요"
        assert response.headers["X-Account-Status"] == "suspended"


def test_lifting_the_suspension_restores_access(client, world):
    world.my_status = "active"

    assert client.get("/blocks", headers=AUTH).status_code == 200
