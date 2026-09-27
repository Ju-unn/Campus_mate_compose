"""지인(연락처) 차단(조각 6 B4). 서버는 번호의 HMAC 만 저장한다 — 이름은 기기에만 있다.
후보에서 빼는 일은 match_candidates SQL 이 이미 한다(여기서는 저장 · 목록 · 해제만)."""
import logging

from app.signup_policy import IDENTITY_KEY_VERSION, bytea_literal, hash_phone
from fake_supabase import AUTH, ME, STRANGER

KEY = "identity-key-test"


def _hmac(e164: str) -> str:
    return bytea_literal(hash_phone(KEY, e164))


def test_registering_numbers_stores_only_the_hmac_of_the_e164_form(client, world):
    response = client.post("/contact-blocks", headers=AUTH, json={"numbers": ["010-1234-5678"]})

    assert response.status_code == 200
    assert world.contact_blocks[0]["owner_id"] == ME
    assert world.contact_blocks[0]["contact_hmac"] == _hmac("+821012345678")
    assert world.contact_blocks[0]["key_version"] == IDENTITY_KEY_VERSION
    upsert = world.calls("POST", "contact_blocks")[0]
    assert upsert.url.params["on_conflict"] == "owner_id,contact_hmac"
    assert upsert.headers["prefer"] == "resolution=merge-duplicates,return=representation"


def test_the_answer_lines_up_with_the_input_and_skips_non_mobile_numbers(client, world):
    """앱은 기기에 (이름, id) 를 짝짓는다 — 같은 길이 · 같은 순서, 휴대전화가 아닌 자리는 null."""
    response = client.post("/contact-blocks", headers=AUTH,
                           json={"numbers": ["02-123-4567", "010-1111-2222", "01033334444"]})

    blocks = response.json()["blocks"]
    assert len(blocks) == 3
    assert blocks[0] is None
    assert set(blocks[1]) == {"id", "created_at"}
    assert blocks[1]["id"] != blocks[2]["id"]
    assert len(world.contact_blocks) == 2
    row_1111 = next(b for b in world.contact_blocks if b["contact_hmac"] == _hmac("+821011112222"))
    assert row_1111["id"] == blocks[1]["id"]
    row_3333 = next(b for b in world.contact_blocks if b["contact_hmac"] == _hmac("+821033334444"))
    assert row_3333["id"] == blocks[2]["id"]


def test_the_same_number_twice_in_one_request_is_sent_once(client, world):
    """PostgREST 는 한 배치에 같은 키가 두 번 오면 `cannot affect row a second time` 으로 통째로 실패한다."""
    response = client.post("/contact-blocks", headers=AUTH,
                           json={"numbers": ["010-1234-5678", "+82 10-1234-5678"]})

    assert response.status_code == 200
    first, second = response.json()["blocks"]
    assert first == second
    assert len(world.contact_blocks) == 1


def test_a_number_already_blocked_gets_its_existing_id_back(client, world):
    world.contact_blocks.append({
        "owner_id": ME, "contact_hmac": _hmac("+821012345678"), "key_version": 1,
        "id": "99999999-9999-9999-9999-999999999999", "created_at": "2026-09-01T10:00:00+09:00",
    })

    response = client.post("/contact-blocks", headers=AUTH, json={"numbers": ["01012345678"]})

    assert response.json()["blocks"] == [
        {"id": "99999999-9999-9999-9999-999999999999", "created_at": "2026-09-01T10:00:00+09:00"},
    ]
    assert len(world.contact_blocks) == 1


def test_only_non_mobile_numbers_touch_nothing(client, world):
    response = client.post("/contact-blocks", headers=AUTH, json={"numbers": ["02-123-4567", ""]})

    assert response.json() == {"blocks": [None, None]}
    assert world.calls("POST", "contact_blocks") == []


def test_the_batch_size_is_1_to_200(client, world):
    assert client.post("/contact-blocks", headers=AUTH, json={"numbers": []}).status_code == 422
    too_many = [f"010{n:08d}" for n in range(201)]
    assert client.post("/contact-blocks", headers=AUTH, json={"numbers": too_many}).status_code == 422
    assert client.post("/contact-blocks", headers=AUTH, json={"numbers": too_many[:200]}).status_code == 200


def test_neither_the_answer_nor_the_log_carries_numbers_or_hashes(client, world, caplog):
    with caplog.at_level(logging.DEBUG):
        response = client.post("/contact-blocks", headers=AUTH, json={"numbers": ["010-1234-5678"]})

    digest = hash_phone(KEY, "+821012345678").hex()
    for text in (response.text, caplog.text):
        assert "1234" not in text
        assert digest not in text


def test_the_list_is_mine_newest_first_with_id_and_date_only(client, world):
    world.contact_blocks += [
        {"owner_id": ME, "contact_hmac": "\\x01", "key_version": 1,
         "id": "00000000-0000-0000-0000-00000000000a", "created_at": "2026-09-01T10:00:00+09:00"},
        {"owner_id": ME, "contact_hmac": "\\x02", "key_version": 1,
         "id": "00000000-0000-0000-0000-00000000000b", "created_at": "2026-09-02T10:00:00+09:00"},
        {"owner_id": STRANGER, "contact_hmac": "\\x03", "key_version": 1,
         "id": "00000000-0000-0000-0000-00000000000c", "created_at": "2026-09-03T10:00:00+09:00"},
    ]

    response = client.get("/contact-blocks", headers=AUTH)

    assert response.json() == {"blocks": [
        {"id": "00000000-0000-0000-0000-00000000000b", "created_at": "2026-09-02T10:00:00+09:00"},
        {"id": "00000000-0000-0000-0000-00000000000a", "created_at": "2026-09-01T10:00:00+09:00"},
    ]}
    read = world.calls("GET", "contact_blocks")[0].url.params
    assert read["order"] == "created_at.desc"
    assert read["limit"] == "1000"
    assert "contact_hmac" not in read["select"]


def test_unblocking_needs_the_owner_to_match_and_is_idempotent(client, world):
    mine = "00000000-0000-0000-0000-00000000000a"
    theirs = "00000000-0000-0000-0000-00000000000c"
    world.contact_blocks += [
        {"owner_id": ME, "contact_hmac": "\\x01", "key_version": 1, "id": mine, "created_at": "t"},
        {"owner_id": STRANGER, "contact_hmac": "\\x03", "key_version": 1, "id": theirs, "created_at": "t"},
    ]

    assert client.delete(f"/contact-blocks/{mine}", headers=AUTH).json() == {"ok": True}
    assert client.delete(f"/contact-blocks/{mine}", headers=AUTH).status_code == 200
    assert client.delete(f"/contact-blocks/{theirs}", headers=AUTH).status_code == 200

    assert [b["id"] for b in world.contact_blocks] == [theirs]
    assert world.calls("DELETE", "contact_blocks")[0].url.params["owner_id"] == f"eq.{ME}"


def test_unblocking_a_malformed_id_is_422(client, world):
    assert client.delete("/contact-blocks/not-a-uuid", headers=AUTH).status_code == 422


def test_all_three_need_a_verified_account(client, world):
    world.my_status = "suspended"

    for response in (client.post("/contact-blocks", headers=AUTH, json={"numbers": ["01012345678"]}),
                     client.get("/contact-blocks", headers=AUTH),
                     client.delete("/contact-blocks/00000000-0000-0000-0000-00000000000a", headers=AUTH)):
        assert response.status_code == 403
