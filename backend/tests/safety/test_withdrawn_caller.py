"""탈퇴한 계정은 모든 인증 API 에서 401 + `X-Account-Status: withdrawn` 이다(편차 1, 정지 403 과 같은 방식).
상대에게는 나간 사람과 같은 모양으로 보인다(chat/gate.is_gone)."""
from fake_supabase import AUTH, MATCH_ID, PARTNER


def test_a_withdrawn_caller_gets_401_and_the_header_on_verified_apis(client, world):
    world.my_status = "withdrawn"

    for response in (client.get("/blocks", headers=AUTH),
                     client.get(f"/profiles/{PARTNER}", headers=AUTH),
                     client.get("/cards/today", headers=AUTH)):
        assert response.status_code == 401
        assert response.json()["detail"] == "탈퇴한 계정이에요"
        assert response.headers["X-Account-Status"] == "withdrawn"


def test_a_withdrawn_partner_looks_like_one_who_left_even_after_the_gate(client, world):
    world.match["trust_passed_at"] = "2126-09-23T10:00:00+09:00"
    world.match["match_participants"][1]["profiles"] = {"status": "withdrawn"}

    body = client.get(f"/chat/matches/{MATCH_ID}", headers=AUTH).json()

    assert body["gate"]["partner_left"] is True
    assert "kakao_id" not in body
    assert "photo_urls" not in body
