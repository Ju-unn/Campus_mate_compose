"""관리자 탈퇴 대행의 카카오 연결 끊기(app/account/social_unlink.py unlink_kakao_for_user) — 본인 토큰 없이 auth 관리자 API 로 회원번호를 읽는다."""
from urllib.parse import parse_qs

import httpx

from admin_world import settings
from app.account.social_unlink import unlink_kakao_for_user

USER = "11111111-0000-0000-0000-000000000001"
KEY = "kakao-admin-test"


async def _run(user: dict | None, *, key: str = KEY, unlink_status: int = 200):
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        if request.url.path == f"/auth/v1/admin/users/{USER}":
            return httpx.Response(200, json=user) if user is not None else httpx.Response(404, json={})
        if request.url.path == "/v1/user/unlink":
            return httpx.Response(unlink_status, json={})
        raise AssertionError(f"모르는 요청 {request.method} {request.url}")

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        try:
            return await unlink_kakao_for_user(settings(kakao_admin_key=key), client, USER), seen
        except httpx.HTTPStatusError:
            return "raised", seen


async def test_a_kakao_account_is_unlinked_with_the_member_id_from_the_admin_api():
    user = {"identities": [{"provider": "google", "identity_data": {"sub": "g"}},
                           {"provider": "kakao", "identity_data": {"sub": 4242}}]}

    done, seen = await _run(user)

    assert done is True
    unlink = seen[-1]
    assert unlink.headers["authorization"] == f"KakaoAK {KEY}"
    assert parse_qs(unlink.content.decode()) == {"target_id_type": ["user_id"], "target_id": ["4242"]}
    # 관리자 API 는 service_role 키로 부른다(사용자 토큰이 아니다).
    assert seen[0].headers["authorization"] == "Bearer service-key"


async def test_no_key_skips_everything():
    done, seen = await _run({"identities": [{"provider": "kakao", "identity_data": {"sub": "1"}}]}, key="")

    assert done is False and seen == []


async def test_a_non_kakao_account_is_not_unlinked():
    done, seen = await _run({"identities": [{"provider": "apple", "identity_data": {"sub": "a"}}]})

    assert done is False and [r.url.path for r in seen] == [f"/auth/v1/admin/users/{USER}"]


async def test_a_kakao_refusal_raises_so_the_caller_can_record_the_failure():
    done, _ = await _run({"identities": [{"provider": "kakao", "identity_data": {"sub": "1"}}]}, unlink_status=500)

    assert done == "raised"
