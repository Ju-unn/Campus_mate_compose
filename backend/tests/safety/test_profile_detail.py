"""14c 상대 프로필(GET /profiles/{profile_id}). 10b 카드 상세와 같은 몸통 + 게이트 뒤 연락처."""
import pytest

from fake_supabase import AUTH, ME, MATCH_ID, PARTNER, STRANGER

DETAIL_KEYS = {
    "match_id", "profile", "survey", "animal_type", "impression_type", "religion", "is_smoker",
    "interests", "my_traits", "ideal_traits", "height_cm", "mbti", "student_number", "bio", "ideal_note",
}


def test_before_the_gate_there_is_no_contact(client, world):
    response = client.get(f"/profiles/{PARTNER}", headers=AUTH)

    assert response.status_code == 200
    body = response.json()
    # 키 자체가 없어야 한다 — null 로라도 내려가면 앱이 자리를 그린다(채팅방 머리말과 같은 규칙).
    assert set(body) == DETAIL_KEYS
    assert body["match_id"] == MATCH_ID
    assert body["profile"] == {
        "profile_id": PARTNER, "nickname": "여우비", "age": 24, "university": "테스트대학교",
        "major": "컴퓨터공학과",
        "avatar_url": "https://x.supabase.co/storage/v1/object/public/avatars/p2/a.png",
    }
    assert body["interests"] == ["영화"]
    assert body["survey"][0] == 0.5


def test_after_the_gate_kakao_id_and_signed_photos_are_added(client, world):
    world.match["trust_passed_at"] = "2126-09-23T10:00:00+09:00"

    body = client.get(f"/profiles/{PARTNER}", headers=AUTH).json()

    assert set(body) == DETAIL_KEYS | {"kakao_id", "photo_urls"}
    assert body["kakao_id"] == "fox_rain"
    assert body["photo_urls"] == [
        "https://x.supabase.co/storage/v1/object/sign/profile-photos/p2/1.jpg?token=t",
        "https://x.supabase.co/storage/v1/object/sign/profile-photos/p2/2.jpg?token=t",
    ]


def test_it_is_the_card_detail_body_with_match_id_instead_of_card_id(client, world):
    """두 엔드포인트가 한 함수로 같은 dict 를 만든다 — 한쪽만 키가 늘면 앱 모델이 갈라진다."""
    card = client.get("/cards/card-1", headers=AUTH).json()
    partner = client.get(f"/profiles/{PARTNER}", headers=AUTH).json()

    assert card.pop("card_id") == "card-1"
    assert partner.pop("match_id") == MATCH_ID
    assert card == partner


def test_an_auto_hidden_partner_is_still_shown(client, world):
    """결정 3: 자동 가림은 카드에서만 빠진다. 진행 중인 채팅의 상대 프로필은 그대로다."""
    world.profiles[PARTNER]["auto_hidden_at"] = "2026-09-26T10:00:00+09:00"

    assert client.get(f"/profiles/{PARTNER}", headers=AUTH).status_code == 200


def _left(who: int):
    def change(world):
        world.match["match_participants"][who]["left_at"] = "2126-09-23T10:00:00+09:00"
    return change


@pytest.mark.parametrize("target, change", [
    pytest.param(ME, lambda w: None, id="자기 자신"),
    pytest.param(STRANGER, lambda w: None, id="매칭 이력 없음"),
    pytest.param(PARTNER, _left(0), id="내가 나감"),
    # 상대가 나간 방도 404 다. "나를 차단한 상대"(나간 것처럼 보인다)와 "그냥 나간 상대"가 14c 에서
    # 갈리면 차단 사실이 샌다(설계 §7.2, 편차 ②).
    pytest.param(PARTNER, _left(1), id="상대가 나감"),
    pytest.param(PARTNER, lambda w: w.blocks.append(
        {"blocker_id": ME, "blocked_id": PARTNER, "created_at": "2026-09-27T09:00:00+09:00"}), id="내가 차단"),
    pytest.param(PARTNER, lambda w: w.blocks.append(
        {"blocker_id": PARTNER, "blocked_id": ME, "created_at": "2026-09-27T09:00:00+09:00"}), id="상대가 차단"),
    pytest.param(PARTNER, lambda w: w.profiles[PARTNER].update(status="suspended"), id="상대 정지"),
    pytest.param(PARTNER, lambda w: w.profiles[PARTNER].update(status="withdrawn"), id="상대 탈퇴"),
])
def test_every_hidden_case_is_the_same_404(client, world, target, change):
    change(world)

    response = client.get(f"/profiles/{target}", headers=AUTH)

    assert response.status_code == 404
    assert response.json()["detail"] == "프로필을 찾을 수 없어요"
