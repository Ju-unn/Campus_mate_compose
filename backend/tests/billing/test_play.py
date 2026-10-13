"""구글 플레이 개발자 API 창구(billing/play.py). 실제 구글은 부르지 않는다 — httpx.MockTransport 로 답을 정한다."""
import hashlib
import logging
from uuid import UUID

import httpx
import pytest

from app.billing.play import PACKAGE_NAME, PlayApi, PlayUnavailable, account_token, token_hash

PROFILE = UUID("11111111-1111-1111-1111-111111111111")
TOKEN = "opaque-token.AbC_123-xyz"


def test_account_token_is_64_hex_and_hides_the_profile_id():
    token = account_token(PROFILE)
    assert len(token) == 64 and all(c in "0123456789abcdef" for c in token)
    assert str(PROFILE) not in token
    assert token == hashlib.sha256(f"campusmate-play:{PROFILE}".encode()).hexdigest()


def test_account_token_is_the_same_for_a_uuid_and_its_string():
    # 상점(status)은 UUID 를, 확인(verify)은 같은 UUID 를 쓴다 — 모양이 달라도 값이 같아야 대조가 맞는다.
    assert account_token(PROFILE) == account_token(str(PROFILE))


def test_token_hash_is_sha256_hex_of_the_raw_token():
    assert token_hash("abc.DEF-1_2") == hashlib.sha256(b"abc.DEF-1_2").hexdigest()


def test_the_package_is_the_android_application_id():
    assert PACKAGE_NAME == "io.github.juunn.campusmate"


def _api(handler, seen: list | None = None) -> PlayApi:
    def wrapped(request: httpx.Request) -> httpx.Response:
        if seen is not None:
            seen.append(request)
        return handler(request)

    async def fixed_token() -> str:
        return "play-access-token"

    return PlayApi(httpx.AsyncClient(transport=httpx.MockTransport(wrapped)), access_token=fixed_token)


async def test_get_purchase_asks_google_for_this_app_product_and_token_with_a_timeout():
    seen: list[httpx.Request] = []
    api = _api(lambda r: httpx.Response(200, json={"purchaseState": 0}), seen)

    assert await api.get_purchase("heart_100", TOKEN) == {"purchaseState": 0}
    (request,) = seen
    assert request.method == "GET"
    assert request.url.host == "androidpublisher.googleapis.com"
    assert request.url.path == (f"/androidpublisher/v3/applications/{PACKAGE_NAME}"
                                f"/purchases/products/heart_100/tokens/{TOKEN}")
    assert request.headers["Authorization"] == "Bearer play-access-token"
    # 시간 제한을 비워 두면 구글이 늦을 때 요청이 끝없이 매달린다 — 모든 호출에 명시한다.
    assert request.extensions["timeout"]["read"] == 10.0


@pytest.mark.parametrize("status", [400, 404, 410])
async def test_get_purchase_is_none_when_google_does_not_know_the_token(status):
    assert await _api(lambda r: httpx.Response(status, json={"error": {}})).get_purchase("heart_100", TOKEN) is None


@pytest.mark.parametrize("status", [500, 503, 429, 401, 403])
async def test_get_purchase_is_unavailable_on_outage_or_our_permission_problem(status):
    with pytest.raises(PlayUnavailable):
        await _api(lambda r: httpx.Response(status)).get_purchase("heart_100", TOKEN)


async def test_a_timeout_is_unavailable_and_the_error_does_not_carry_the_token():
    def slow(request):
        raise httpx.ReadTimeout(f"timed out {request.url}", request=request)

    with pytest.raises(PlayUnavailable) as caught:
        await _api(slow).get_purchase("heart_100", TOKEN)
    assert TOKEN not in str(caught.value)
    # from None — 원래 예외(주소에 토큰)가 __context__ 로 따라 올라가 트레이스백에 찍히지 않게 한다.
    assert caught.value.__cause__ is None and caught.value.__suppress_context__


async def test_consume_posts_to_the_consume_address_and_reports_success():
    seen: list[httpx.Request] = []
    api = _api(lambda r: httpx.Response(200), seen)

    assert await api.consume("heart_100", TOKEN) is True
    (request,) = seen
    assert request.method == "POST"
    assert request.url.path.endswith(f"/purchases/products/heart_100/tokens/{TOKEN}:consume")
    assert request.extensions["timeout"]["read"] == 10.0


@pytest.mark.parametrize("response", [httpx.Response(500), httpx.Response(400)])
async def test_consume_failure_is_false_not_an_exception(response):
    assert await _api(lambda r: response).consume("heart_100", TOKEN) is False


async def test_voided_since_follows_every_page():
    pages = {
        None: {"voidedPurchases": [{"purchaseToken": "t1"}], "tokenPagination": {"nextPageToken": "p2"}},
        "p2": {"voidedPurchases": [{"purchaseToken": "t2"}]},
    }
    seen: list[httpx.Request] = []
    api = _api(lambda r: httpx.Response(200, json=pages[r.url.params.get("token")]), seen)

    assert await api.voided_since(1_760_000_000_000) == [{"purchaseToken": "t1"}, {"purchaseToken": "t2"}]
    assert [r.url.path for r in seen] == [f"/androidpublisher/v3/applications/{PACKAGE_NAME}/purchases/voidedpurchases"] * 2
    assert seen[0].url.params["startTime"] == "1760000000000" and seen[0].url.params["type"] == "0"
    assert "token" not in seen[0].url.params and seen[1].url.params["token"] == "p2"


async def test_voided_since_with_nothing_voided_is_empty():
    assert await _api(lambda r: httpx.Response(200, json={})).voided_since(0) == []


@pytest.mark.parametrize("status", [400, 500])
async def test_voided_since_failure_is_unavailable(status):
    with pytest.raises(PlayUnavailable):
        await _api(lambda r: httpx.Response(status)).voided_since(0)


def test_httpx_request_lines_are_never_logged_at_info():
    # httpx 는 INFO 로 요청 주소를 찍는데 그 주소에 구매 토큰이 있다 — 누가 INFO 를 켜도 새지 않게 못박는다.
    # 루트 수준(effective)이 아니라 httpx 자기 수준을 본다 — 루트를 DEBUG 로 내려도 막혀 있어야 한다.
    assert logging.getLogger("httpx").level >= logging.WARNING
