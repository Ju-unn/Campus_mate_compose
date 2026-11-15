"""홈 리뷰 띠의 실제 스토어 별점(2026-11-16 사용자 결정 — 실제 스토어 값만, 못 읽으면 0명 상태).

바깥 호출(애플 공개 조회 · Cloud Storage 의 플레이 별점 보고서)은 모두 가짜 전송으로 바꾼다 — 실제 네트워크를 부르지 않는다."""
import asyncio
from datetime import date

import httpx
import pytest

from app.home import store_ratings
from app.home.store_ratings import EMPTY, StoreRatings

APPLE_HOST = "itunes.apple.com"
GCS_HOST = "storage.googleapis.com"
BUCKET = "reports-bucket"
TODAY = date(2026, 11, 16)


def _apple(rating=5, count=1, status=200) -> httpx.Response:
    if status != 200:
        return httpx.Response(status)
    return httpx.Response(200, json={"resultCount": 1, "results": [{"averageUserRating": rating, "userRatingCount": count}]})


def _csv(rows: list[tuple[str, str]], encoding: str = "utf-16") -> bytes:
    lines = ["Date,Package Name,Daily Average Rating,Total Average Rating"]
    lines += [f"{day},io.github.juunn.campusmate,,{total}" for day, total in rows]
    return ("\n".join(lines) + "\n").encode(encoding)


def _client(apple: httpx.Response | None = None, objects: dict[str, bytes] | None = None,
            seen: list[httpx.Request] | None = None, gcs_error: Exception | None = None) -> httpx.AsyncClient:
    def handler(request: httpx.Request) -> httpx.Response:
        if seen is not None:
            seen.append(request)
        if request.url.host == APPLE_HOST:
            return apple or _apple()
        if request.url.host == GCS_HOST:
            if gcs_error is not None:
                raise gcs_error
            # url.path 는 %2F 를 풀어 보인다 — 실제로 나가는 모양(raw_path)으로 본다.
            name = _raw_path(request).rsplit("/o/", 1)[1]
            body = (objects or {}).get(name)
            return httpx.Response(200, content=body) if body is not None else httpx.Response(404)
        return httpx.Response(404)
    return httpx.AsyncClient(transport=httpx.MockTransport(handler))


def _raw_path(request: httpx.Request) -> str:
    return request.url.raw_path.decode().split("?", 1)[0]


def _object(month: str) -> str:
    # 경로 조각의 '/' 는 %2F 로 보낸다(Cloud Storage JSON API 의 객체 이름 규칙).
    return f"stats%2Fratings%2Fratings_io.github.juunn.campusmate_{month}_overview.csv"


async def _token() -> str:
    return "token-abc"


def _fresh() -> StoreRatings:
    return StoreRatings(access_token=_token, today=lambda: TODAY)


def _run(coro):
    return asyncio.run(coro)


def test_ios_reads_the_apple_public_lookup():
    seen: list[httpx.Request] = []
    result = _run(_fresh().get(_client(apple=_apple(4.5, 12), seen=seen), bucket=""))

    assert result["ios"] == {"rating": 4.5, "count": 12}
    lookup = next(r for r in seen if r.url.host == APPLE_HOST)
    assert lookup.url.path == "/lookup"
    assert dict(lookup.url.params) == {"id": "6821955396", "country": "kr"}


@pytest.mark.parametrize("apple", [
    _apple(status=500),
    httpx.Response(200, json={"resultCount": 0, "results": []}),
    httpx.Response(200, json={"resultCount": 1, "results": [{}]}),  # 아직 평가가 없는 앱은 칸이 없다
    httpx.Response(200, content=b"not json"),
])
def test_ios_falls_back_to_zero_when_apple_has_nothing_usable(apple):
    assert _run(_fresh().get(_client(apple=apple), bucket=""))["ios"] == EMPTY


def test_android_is_zero_without_a_bucket_and_never_calls_storage():
    seen: list[httpx.Request] = []
    result = _run(_fresh().get(_client(seen=seen), bucket=""))

    assert result["android"] == EMPTY
    assert not any(r.url.host == GCS_HOST for r in seen)


def test_android_reads_the_last_filled_total_average_of_this_months_utf16_report():
    seen: list[httpx.Request] = []
    objects = {_object("202611"): _csv([("2026-11-14", "4.20"), ("2026-11-15", "4.50"), ("2026-11-16", "")])}
    result = _run(_fresh().get(_client(objects=objects, seen=seen), bucket=BUCKET))

    # 플레이 보고서에는 평가 수가 없다 — count 는 null(앱이 "(N명 평가)" 를 숨긴다).
    assert result["android"] == {"rating": 4.5, "count": None}
    call = next(r for r in seen if r.url.host == GCS_HOST)
    assert _raw_path(call) == f"/storage/v1/b/{BUCKET}/o/{_object('202611')}"
    assert call.url.params["alt"] == "media"
    assert call.headers["Authorization"] == "Bearer token-abc"


def test_android_uses_last_month_when_this_months_report_is_not_there_yet():
    objects = {_object("202610"): _csv([("2026-10-31", "3.90")])}
    assert _run(_fresh().get(_client(objects=objects), bucket=BUCKET))["android"] == {"rating": 3.9, "count": None}


def test_android_last_month_rolls_back_over_the_new_year():
    january = StoreRatings(access_token=_token, today=lambda: date(2027, 1, 2))
    objects = {_object("202612"): _csv([("2026-12-31", "4.00")])}
    assert _run(january.get(_client(objects=objects), bucket=BUCKET))["android"] == {"rating": 4.0, "count": None}


def test_android_also_reads_a_utf8_report():
    objects = {_object("202611"): _csv([("2026-11-15", "4.10")], encoding="utf-8-sig")}
    assert _run(_fresh().get(_client(objects=objects), bucket=BUCKET))["android"] == {"rating": 4.1, "count": None}


@pytest.mark.parametrize("objects", [
    {},  # 두 달 모두 없음
    {_object("202611"): _csv([("2026-11-15", "")])},  # 평점 칸이 모두 비어 있음
    {_object("202611"): b"\xff\xfe" + "아무 글".encode("utf-16-le")},  # 열이 다름
    {_object("202611"): _csv([("2026-11-15", "9.10")])},  # 1~5 밖
])
def test_android_falls_back_to_zero_when_the_report_has_nothing_usable(objects):
    assert _run(_fresh().get(_client(objects=objects), bucket=BUCKET))["android"] == EMPTY


def test_android_falls_back_to_zero_when_storage_or_auth_fails():
    failing = _client(gcs_error=httpx.ConnectTimeout("slow"))
    assert _run(_fresh().get(failing, bucket=BUCKET))["android"] == EMPTY

    async def no_token() -> str:
        raise RuntimeError("no adc")

    broken = StoreRatings(access_token=no_token, today=lambda: TODAY)
    assert _run(broken.get(_client(objects={_object("202611"): _csv([("2026-11-15", "4.5")])}), bucket=BUCKET))["android"] == EMPTY


def test_values_are_cached_so_requests_do_not_go_out_every_time():
    seen: list[httpx.Request] = []
    ratings = _fresh()
    client = _client(objects={_object("202611"): _csv([("2026-11-15", "4.5")])}, seen=seen)

    first = _run(ratings.get(client, bucket=BUCKET))
    second = _run(ratings.get(client, bucket=BUCKET))

    assert first == second == {"ios": {"rating": 5.0, "count": 1}, "android": {"rating": 4.5, "count": None}}
    assert [r.url.host for r in seen].count(APPLE_HOST) == 1
    assert [r.url.host for r in seen].count(GCS_HOST) == 1


def test_a_failure_is_cached_only_briefly_then_tried_again():
    seen: list[httpx.Request] = []
    clock = [1000.0]
    ratings = StoreRatings(access_token=_token, today=lambda: TODAY, monotonic=lambda: clock[0])
    client = _client(apple=_apple(status=503), seen=seen)

    _run(ratings.get(client, bucket=""))
    _run(ratings.get(client, bucket=""))
    assert [r.url.host for r in seen].count(APPLE_HOST) == 1  # 실패도 잠깐은 기억한다

    clock[0] += store_ratings.FAILURE_TTL_SECONDS + 1
    _run(ratings.get(client, bucket=""))
    assert [r.url.host for r in seen].count(APPLE_HOST) == 2


def test_success_is_kept_for_hours():
    seen: list[httpx.Request] = []
    clock = [1000.0]
    ratings = StoreRatings(access_token=_token, today=lambda: TODAY, monotonic=lambda: clock[0])
    client = _client(seen=seen)

    _run(ratings.get(client, bucket=""))
    clock[0] += store_ratings.FAILURE_TTL_SECONDS + 1
    _run(ratings.get(client, bucket=""))
    assert [r.url.host for r in seen].count(APPLE_HOST) == 1
    clock[0] += store_ratings.SUCCESS_TTL_SECONDS
    _run(ratings.get(client, bucket=""))
    assert [r.url.host for r in seen].count(APPLE_HOST) == 2
    assert store_ratings.SUCCESS_TTL_SECONDS >= 3600


# 검토 지적(2026-11-16): 실물 보고서의 머리 글자 · 압축 · 빈 값과 지연 ---------------------------------------------

def _report(header: str, values: list[str]) -> bytes:
    lines = [header] + [f"2026-11-{i + 1:02d},io.github.juunn.campusmate,,{v}" for i, v in enumerate(values)]
    return ("\n".join(lines) + "\n").encode("utf-16")


@pytest.mark.parametrize("header", [
    "Date,Package Name,Daily Average Rating,TOTAL AVERAGE RATING",  # 대소문자가 다르다
    "Date, Package Name , Daily Average Rating , Total Average Rating ",  # 머리 앞뒤 공백
])
def test_android_finds_the_rating_column_regardless_of_case_and_spaces(header):
    objects = {_object("202611"): _report(header, ["4.40"])}
    assert _run(_fresh().get(_client(objects=objects), bucket=BUCKET))["android"] == {"rating": 4.4, "count": None}


def test_android_without_the_rating_column_is_zero_and_warns_once_without_the_bucket_or_path(caplog):
    objects = {_object("202611"): _report("Date,Package Name,Daily Average Rating", ["4.40"]),
               _object("202610"): _report("Date,Package Name,Daily Average Rating", ["4.40"])}
    with caplog.at_level("WARNING", logger="app.home.store_ratings"):
        result = _run(_fresh().get(_client(objects=objects), bucket=BUCKET))

    assert result["android"] == EMPTY
    warnings = [r.getMessage() for r in caplog.records if "열" in r.getMessage()]
    assert len(warnings) == 1
    assert "android" in warnings[0] and "daily average rating" in warnings[0].lower()
    assert BUCKET not in warnings[0] and "stats/" not in warnings[0] and "ratings_" not in warnings[0]


def test_android_reads_a_gzip_body_without_a_content_encoding_header():
    import gzip
    objects = {_object("202611"): gzip.compress(_csv([("2026-11-15", "4.30")]))}
    assert _run(_fresh().get(_client(objects=objects), bucket=BUCKET))["android"] == {"rating": 4.3, "count": None}


def test_android_uses_the_last_value_that_reads_as_a_number():
    objects = {_object("202611"): _report("Date,Package Name,Daily Average Rating,Total Average Rating",
                                          ["4.10", "4.60", "NA"])}
    assert _run(_fresh().get(_client(objects=objects), bucket=BUCKET))["android"] == {"rating": 4.6, "count": None}


def test_both_stores_are_fetched_at_the_same_time():
    import time as _time

    delay = 0.4

    async def slow(request: httpx.Request) -> httpx.Response:
        await asyncio.sleep(delay)
        if request.url.host == APPLE_HOST:
            return _apple()
        return httpx.Response(200, content=_csv([("2026-11-15", "4.50")]))

    client = httpx.AsyncClient(transport=httpx.MockTransport(slow))
    started = _time.monotonic()
    result = _run(_fresh().get(client, bucket=BUCKET))
    elapsed = _time.monotonic() - started

    assert result == {"ios": {"rating": 5.0, "count": 1}, "android": {"rating": 4.5, "count": None}}
    # 차례로 받으면 두 배(0.8) 넘게 걸린다 — 동시에 받으면 한 쪽 시간 + 여유.
    assert elapsed < delay * 1.6, elapsed
