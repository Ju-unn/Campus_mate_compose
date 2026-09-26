"""차단 · 차단 목록(16f). 차단당한 쪽은 알 수 없다 — 상대에게는 나가기와 글자까지 같은 모양이다."""
from fake_supabase import AUTH, ME, MATCH_ID, PARTNER, STRANGER


def test_blocking_inserts_one_row_idempotently(client, world):
    response = client.post(f"/blocks/{PARTNER}", headers=AUTH)

    assert response.status_code == 200
    assert response.json() == {"ok": True}
    assert world.blocks[0]["blocker_id"] == ME
    assert world.blocks[0]["blocked_id"] == PARTNER
    insert = world.calls("POST", "blocks")[0]
    # 이미 있으면 조용히 성공 — PK 충돌이 409 로 새어 나가지 않는다.
    assert "resolution=ignore-duplicates" in insert.headers["prefer"]


def test_blocking_twice_is_still_200(client, world):
    assert client.post(f"/blocks/{PARTNER}", headers=AUTH).status_code == 200
    assert client.post(f"/blocks/{PARTNER}", headers=AUTH).status_code == 200
    assert len(world.blocks) == 1


def test_blocking_leaves_the_room_exactly_like_leave(client, world):
    """설계 §7.2: 상대 화면에 '나갔어요' 와 구별되는 흔적이 남으면 차단 사실이 샌다."""
    client.post(f"/blocks/{PARTNER}", headers=AUTH)

    patch = world.calls("PATCH", "match_participants")[0]
    assert patch.url.params["profile_id"] == f"eq.{ME}"
    assert patch.url.params["left_at"] == "is.null"
    assert world.posted_messages == [{
        "match_id": MATCH_ID, "sender_id": ME, "kind": "left", "body": "나나님이 채팅방을 나갔어요",
    }]


def test_blocking_after_i_already_left_skips_the_room(client, world):
    world.match["match_participants"][0]["left_at"] = "2126-09-22T12:00:00+09:00"

    assert client.post(f"/blocks/{PARTNER}", headers=AUTH).status_code == 200
    assert world.calls("PATCH", "match_participants") == []
    assert world.posted_messages == []
    assert len(world.blocks) == 1


def test_blocking_a_closed_room_skips_the_room(client, world):
    world.match["chat_closed_at"] = "2126-09-24T10:00:00+09:00"

    assert client.post(f"/blocks/{PARTNER}", headers=AUTH).status_code == 200
    assert world.calls("PATCH", "match_participants") == []
    assert world.posted_messages == []
    assert len(world.blocks) == 1


def test_blocking_someone_i_never_matched_is_404(client, world):
    response = client.post(f"/blocks/{STRANGER}", headers=AUTH)

    assert response.status_code == 404
    assert response.json()["detail"] == "프로필을 찾을 수 없어요"
    assert world.blocks == []


def test_blocking_myself_is_404(client, world):
    response = client.post(f"/blocks/{ME}", headers=AUTH)

    assert response.status_code == 404
    assert response.json()["detail"] == "프로필을 찾을 수 없어요"
    assert world.blocks == []


def test_block_list_shows_nickname_avatar_and_date_newest_first(client, world):
    client.post(f"/blocks/{PARTNER}", headers=AUTH)

    response = client.get("/blocks", headers=AUTH)

    assert response.status_code == 200
    assert response.json() == {"blocks": [{
        "profile_id": PARTNER,
        "nickname": "여우비",
        # ready 중 최신 — failed 는 더 최신이어도 건너뛴다(카드 · 채팅과 같은 규칙).
        "avatar_url": "https://x.supabase.co/storage/v1/object/public/avatars/p2/a.png",
        "blocked_at": "2026-09-27T10:00:00+09:00",
    }]}
    query = world.calls("GET", "blocks")[-1].url.params
    assert query["blocker_id"] == f"eq.{ME}"
    assert query["order"] == "created_at.desc"
    # PostgREST db-max-rows 에 조용히 잘리지 않게 상한을 우리가 건다.
    assert int(query["limit"]) == 200


def test_block_list_has_no_real_photos_or_reasons(client, world):
    world.profiles[PARTNER]["profile_avatars"] = []
    client.post(f"/blocks/{PARTNER}", headers=AUTH)

    row = client.get("/blocks", headers=AUTH).json()["blocks"][0]

    assert set(row) == {"profile_id", "nickname", "avatar_url", "blocked_at"}
    assert row["avatar_url"] is None


def test_unblocking_is_200_twice_and_does_not_restore_the_room(client, world):
    client.post(f"/blocks/{PARTNER}", headers=AUTH)

    assert client.delete(f"/blocks/{PARTNER}", headers=AUTH).json() == {"ok": True}
    assert client.delete(f"/blocks/{PARTNER}", headers=AUTH).status_code == 200

    delete = world.calls("DELETE", "blocks")[0].url.params
    assert delete["blocker_id"] == f"eq.{ME}"
    assert delete["blocked_id"] == f"eq.{PARTNER}"
    assert world.blocks == []
    # 대화는 복구하지 않는다(16f) — 해제는 left_at 을 건드리지 않는다.
    assert world.match["match_participants"][0]["left_at"] is not None
    assert len(world.calls("PATCH", "match_participants")) == 1
