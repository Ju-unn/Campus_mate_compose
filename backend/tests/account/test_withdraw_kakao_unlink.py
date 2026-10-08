"""탈퇴 때 카카오 연결 끊기(app/account/social_unlink.py). 진짜 카카오는 부르지 않는다 — 가짜 서버로만 본다.

카카오 회원번호는 `GET /auth/v1/user` 의 identities 중 provider kakao 의 identity_data.sub 다.
실패해도 탈퇴는 그대로 끝나고 경고만 남는다(회원번호와 키는 로그에 남기지 않는다).
"""
import logging
from urllib.parse import parse_qs

from account_world import AUTH, ME
from app.settings import Settings

KEY = "kakao-admin-test"


def test_a_kakao_member_is_unlinked_with_the_admin_key(client, world):
    world.settings_overrides = {"kakao_admin_key": KEY}

    response = client.post("/account/withdraw", headers=AUTH)

    assert response.status_code == 200
    [unlink] = world.kakao_unlinks
    assert str(unlink.url) == "https://kapi.kakao.com/v1/user/unlink"
    assert unlink.headers["authorization"] == f"KakaoAK {KEY}"
    assert unlink.headers["content-type"].startswith("application/x-www-form-urlencoded")
    assert parse_qs(unlink.content.decode()) == {"target_id_type": ["user_id"], "target_id": ["4242"]}


def test_the_member_id_is_read_with_the_users_own_token(client, world):
    world.settings_overrides = {"kakao_admin_key": KEY}

    client.post("/account/withdraw", headers=AUTH)

    reads = world.calls("GET", "/auth/v1/user")
    assert reads and all(r.headers["authorization"] == AUTH["Authorization"] for r in reads)


def test_unlinking_happens_before_every_session_is_logged_out(client, world):
    """로그아웃 뒤에는 그 토큰으로 /user 를 못 읽을 수 있다 — 연결 끊기를 먼저 한다."""
    world.settings_overrides = {"kakao_admin_key": KEY}

    client.post("/account/withdraw", headers=AUTH)

    order = [r.url.path for r in world.requests if r.url.path in ("/v1/user/unlink", "/auth/v1/logout")]
    assert order == ["/v1/user/unlink", "/auth/v1/logout"]


def test_no_key_skips_the_call(client, world):
    assert client.post("/account/withdraw", headers=AUTH).status_code == 200
    assert world.kakao_unlinks == []


def test_a_non_kakao_account_skips_the_call(client, world):
    world.settings_overrides = {"kakao_admin_key": KEY}
    world.identities = [{"provider": "google", "identity_data": {"sub": "g-1"}},
                        {"provider": "email", "identity_data": {"sub": ME}}]

    assert client.post("/account/withdraw", headers=AUTH).status_code == 200
    assert world.kakao_unlinks == []


def test_a_kakao_failure_does_not_stop_the_withdrawal(client, world, caplog):
    world.settings_overrides = {"kakao_admin_key": KEY}
    world.kakao_unlink_status = 500

    with caplog.at_level(logging.DEBUG):
        response = client.post("/account/withdraw", headers=AUTH)

    assert response.status_code == 200
    assert world.profiles[ME]["status"] == "withdrawn"
    assert len(world.calls("POST", "/auth/v1/logout")) == 1
    warnings = [r for r in caplog.records if r.levelno == logging.WARNING]
    assert any("kakao" in r.getMessage() for r in warnings)
    # 회원번호와 키는 어느 로그에도 남지 않는다.
    assert "4242" not in caplog.text
    assert KEY not in caplog.text


def test_kakao_unreachable_does_not_stop_the_withdrawal(client, world, caplog):
    world.settings_overrides = {"kakao_admin_key": KEY}
    world.kakao_unreachable = True

    with caplog.at_level(logging.DEBUG):
        response = client.post("/account/withdraw", headers=AUTH)

    assert response.status_code == 200
    assert len(world.calls("POST", "/auth/v1/logout")) == 1
    assert "4242" not in caplog.text


def test_the_admin_key_defaults_to_empty_and_does_not_stop_boot():
    # conftest 가 필수 env 만 채운다 — KAKAO_ADMIN_KEY 가 없어도 뜬다.
    assert Settings().kakao_admin_key == ""
