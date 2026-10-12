"""탈퇴한 계정은 모든 인증 API 에서 401 + `X-Account-Status: withdrawn` 이다(편차 1, 정지 403 과 같은 방식).
상대에게는 나간 사람과 같은 모양으로 보인다(chat/gate.is_gone)."""
import json

from fake_supabase import AUTH, MATCH_ID, ME, PARTNER


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


def test_a_withdrawn_partner_stays_hidden_even_when_the_encrypted_kakao_id_exists(client, world):
    """enc 열로 읽어도 탈퇴한 상대의 카톡 아이디는 나가지 않는다 — 가리는 판정은 읽기 앞이다."""
    world.kakao_ids[PARTNER] = "fox_enc"
    world.match["trust_passed_at"] = "2126-09-23T10:00:00+09:00"
    world.match["match_participants"][1]["profiles"] = {"status": "withdrawn"}

    response = client.get(f"/chat/matches/{MATCH_ID}", headers=AUTH)

    assert "kakao_id" not in response.json()
    assert "fox_enc" not in response.text
    decrypts = [r for r in world.requests if r.url.path.endswith("/rpc/decrypt_profile_private")]
    # 상대 것은 아예 복호화하지 않는다(내 것만).
    assert all(json.loads(r.content)["p_profile"] == ME for r in decrypts)
