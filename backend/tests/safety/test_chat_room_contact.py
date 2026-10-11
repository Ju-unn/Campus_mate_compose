"""게이트를 통과한 방이라도 상대가 나갔거나 · 나를 막았거나 · 정지되면 연락처와 실사진이 닫힌다.

사용자 결정 2026-09-27(검토 I-1): 차단은 차단한 쪽의 left_at 이라 나가기와 같은 판정을 탄다.
두 경우의 응답이 한 글자라도 다르면 상대가 차단을 알아챈다(설계 §7.2). 14c 는 이미 404 다.
"""
from fake_supabase import AUTH, MATCH_ID, ME, PARTNER, FakeSupabase

GATE_PASSED_AT = "2126-09-23T10:00:00+09:00"


def _room(client, world) -> dict:
    world.caller = ME
    response = client.get(f"/chat/matches/{MATCH_ID}", headers=AUTH)
    assert response.status_code == 200
    return response.json()


def _signed_urls(world) -> list:
    return [r for r in world.requests if r.url.path.startswith("/storage/v1/object/sign/")]


def test_the_gate_still_reveals_while_both_stay(client, world):
    world.match["trust_passed_at"] = GATE_PASSED_AT

    body = _room(client, world)

    assert body["kakao_id"] == "fox_rain"
    assert len(body["photo_urls"]) == 2


def test_a_partner_who_left_after_the_gate_takes_the_contact_away(client, world):
    world.match["trust_passed_at"] = GATE_PASSED_AT
    world.caller = PARTNER
    assert client.post(f"/chat/matches/{MATCH_ID}/leave", headers=AUTH).status_code == 200

    body = _room(client, world)

    assert body["gate"]["partner_left"] is True
    assert "kakao_id" not in body
    assert "photo_urls" not in body
    assert _signed_urls(world) == []
    # 내 아이디는 그대로 내려간다(14f 시트).
    assert body["my_kakao_id"] == "my_id"


def test_a_partner_who_blocked_me_after_the_gate_takes_the_contact_away(client, world):
    world.match["trust_passed_at"] = GATE_PASSED_AT
    world.caller = PARTNER
    assert client.post(f"/blocks/{ME}", headers=AUTH).status_code == 200

    body = _room(client, world)

    assert body["gate"]["partner_left"] is True
    assert "kakao_id" not in body
    assert "photo_urls" not in body
    assert _signed_urls(world) == []


def test_leaving_and_blocking_look_exactly_the_same(client, world):
    def room_after(action: str) -> dict:
        fresh = FakeSupabase()
        world.__dict__.update(fresh.__dict__)
        world.match["trust_passed_at"] = GATE_PASSED_AT
        world.caller = PARTNER
        path = f"/chat/matches/{MATCH_ID}/leave" if action == "leave" else f"/blocks/{ME}"
        assert client.post(path, headers=AUTH).status_code == 200
        return _room(client, world)

    left, blocked = room_after("leave"), room_after("block")

    assert set(left) == set(blocked)
    assert left == blocked


def test_a_suspended_partner_after_the_gate_takes_the_contact_away(client, world):
    world.match["trust_passed_at"] = GATE_PASSED_AT
    world.match["match_participants"][1]["profiles"] = {"status": "suspended"}

    body = _room(client, world)

    assert body["gate"]["partner_left"] is True
    assert "kakao_id" not in body
    assert "photo_urls" not in body
    assert _signed_urls(world) == []


def test_the_gate_reveals_the_decrypted_kakao_id_when_only_enc_has_it(client, world):
    """배선 확인 — 방 머리말이 복호화 키를 들고 있어야 enc 열의 값이 나간다."""
    world.kakao_ids.pop(PARTNER)
    world.kakao_ids_enc[PARTNER] = "fox_enc"
    world.kakao_ids_enc[ME] = "my_enc"
    world.match["trust_passed_at"] = GATE_PASSED_AT

    body = _room(client, world)

    assert body["kakao_id"] == "fox_enc"
    assert body["my_kakao_id"] == "my_enc"


def test_the_gate_reveals_the_plain_kakao_id_when_decrypt_is_unavailable(client, world):
    """서버가 DB 보다 먼저 나가 RPC 가 404 여도 채팅방은 평문 열로 그대로 뜬다."""
    world.decrypt_unavailable = True
    world.match["trust_passed_at"] = GATE_PASSED_AT

    body = _room(client, world)

    assert body["kakao_id"] == "fox_rain"
    assert body["my_kakao_id"] == "my_id"
