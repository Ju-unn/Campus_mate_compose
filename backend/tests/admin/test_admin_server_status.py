"""관리자 서버 상태 GET /admin/server-status(설계 2026-11-17-admin-server-status, 계획 Task 1).
구글 모니터링은 부르지 않는다 — 판정 함수는 칸을 직접 넣고, 읽기는 MockTransport, 경로는 가짜 reader 를 끼운다."""
from datetime import UTC, datetime, timedelta

import google.auth.exceptions
import httpx
import pytest

from admin_world import ADMIN, STRANGER, bearer
from app.admin import monitoring
from app.admin.monitoring import Anomaly, Bucket, MonitoringReader, find_anomalies, summarize_now
from app.admin.server_status import get_monitoring_reader
from app.main import app

ADMIN_HEADERS = bearer(sub=ADMIN, aal="aal2")
T0 = datetime(2026, 11, 17, 3, 0, tzinfo=UTC)


def _bucket(i: int = 0, requests: int = 0, errors_5xx: int = 0, p50_ms: int | None = None,
            p95_ms: int | None = None, instances: int | None = None) -> Bucket:
    return Bucket(T0 + timedelta(minutes=5 * i), requests, errors_5xx, p50_ms, p95_ms, instances)


def _empty36() -> list[Bucket]:
    return [_bucket(i) for i in range(36)]


def test_errors_bucket_is_anomaly():
    assert find_anomalies([_bucket(requests=5, errors_5xx=3)]) == [Anomaly(T0, "errors", 3)]


def test_error_rate_needs_20_requests():
    assert find_anomalies([_bucket(requests=19, errors_5xx=2)]) == []
    assert find_anomalies([_bucket(requests=40, errors_5xx=2)]) == [Anomaly(T0, "error_rate", 0.05)]


def test_lone_slow_request_is_not_slow():
    assert find_anomalies([_bucket(requests=3, p50_ms=25000)]) == []
    assert find_anomalies([_bucket(requests=30, p50_ms=1200)]) == [Anomaly(T0, "slow", 1200)]


def test_empty_buckets_are_not_anomalies():
    buckets = _empty36()

    assert find_anomalies(buckets) == []
    now = summarize_now(buckets)
    assert now["requests_per_min"] == 0.0
    assert now["error_rate"] == 0
    assert now["p50_ms"] is None
    assert now["p95_ms"] is None
    assert now["instances"] is None


def test_summarize_now_uses_last_15_minutes():
    buckets = [*_empty36()[:33], _bucket(33, requests=30, errors_5xx=3, p50_ms=200, p95_ms=800, instances=2),
               _bucket(34, requests=45, p50_ms=150, p95_ms=None), _bucket(35)]

    assert summarize_now(buckets) == {"requests_per_min": 5.0, "error_rate": 3 / 75, "p50_ms": 150, "p95_ms": 800,
                                      "instances": 2}


def test_anomalies_newest_first():
    buckets = [_bucket(0, requests=5, errors_5xx=3), _bucket(1), _bucket(2, requests=30, p50_ms=1500)]

    assert [(a.at, a.kind) for a in find_anomalies(buckets)] == [(buckets[2].start, "slow"), (buckets[0].start, "errors")]


# --- 구글 읽기 -------------------------------------------------------------------------------------------------

END = datetime(2026, 11, 17, 12, 7, 30, tzinfo=UTC)  # 5분 내림 → 12:05
SLOT_END = "2026-11-17T12:00:00Z"  # 칸 11:55~12:00 (끝에서 두 번째)


def _series(value: dict, labels: dict | None = None) -> dict:
    return {"metric": {"labels": labels or {}}, "points": [{"interval": {"endTime": SLOT_END}, "value": value}]}


def _monitoring_handler(seen: list[httpx.Request]):
    def handle(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        assert request.url.path == "/v3/projects/test-project/timeSeries"
        assert request.headers["authorization"] == "Bearer fake-token"
        params = request.url.params
        if "request_count" in params["filter"]:
            series = [_series({"int64Value": "10"}, {"response_code_class": "2xx"}),
                      _series({"int64Value": "1"}, {"response_code_class": "5xx"})]
        elif "instance_count" in params["filter"]:
            series = [_series({"int64Value": "2"})]
        elif params["aggregation.crossSeriesReducer"] == "REDUCE_PERCENTILE_50":
            series = [_series({"doubleValue": 120.4})]
        else:
            series = [_series({"doubleValue": 900.0})]
        return httpx.Response(200, json={"timeSeries": series})
    return handle


async def _fake_token() -> str:
    return "fake-token"


async def test_fetch_buckets_maps_points():
    seen: list[httpx.Request] = []
    async with httpx.AsyncClient(transport=httpx.MockTransport(_monitoring_handler(seen))) as http:
        buckets = await MonitoringReader(http, "test-project", _fake_token).fetch_buckets(END)

    assert len(buckets) == 36
    assert buckets[0].start == datetime(2026, 11, 17, 9, 5, tzinfo=UTC)
    assert buckets[-1].start == datetime(2026, 11, 17, 12, 0, tzinfo=UTC)
    assert buckets[-2] == Bucket(datetime(2026, 11, 17, 11, 55, tzinfo=UTC), 11, 1, 120, 900, 2)
    assert buckets[-1] == Bucket(datetime(2026, 11, 17, 12, 0, tzinfo=UTC), 0, 0, None, None, None)

    service = 'resource.type="cloud_run_revision" AND resource.labels.service_name="campus-mate-backend"'
    queries = {(r.url.params["filter"], r.url.params["aggregation.perSeriesAligner"],
                r.url.params["aggregation.crossSeriesReducer"], r.url.params.get("aggregation.groupByFields"))
               for r in seen}
    assert queries == {
        (f'{service} AND metric.type="run.googleapis.com/request_count"', "ALIGN_DELTA", "REDUCE_SUM",
         "metric.labels.response_code_class"),
        (f'{service} AND metric.type="run.googleapis.com/request_latencies"', "ALIGN_DELTA", "REDUCE_PERCENTILE_50", None),
        (f'{service} AND metric.type="run.googleapis.com/request_latencies"', "ALIGN_DELTA", "REDUCE_PERCENTILE_95", None),
        (f'{service} AND metric.type="run.googleapis.com/container/instance_count"', "ALIGN_MAX", "REDUCE_SUM", None),
    }
    for request in seen:
        assert request.url.params["aggregation.alignmentPeriod"] == "300s"
        assert request.url.params["interval.startTime"] == "2026-11-17T09:05:00Z"
        assert request.url.params["interval.endTime"] == "2026-11-17T12:05:00Z"


async def test_fetch_buckets_raises_on_google_error():
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(403, json={}))) as http:
        with pytest.raises(httpx.HTTPStatusError):
            await MonitoringReader(http, "test-project", _fake_token).fetch_buckets(END)


# --- 경로 -------------------------------------------------------------------------------------------------------

class FakeReader:
    def __init__(self) -> None:
        self.calls = 0
        self.error: Exception | None = None

    async def fetch_buckets(self, end: datetime) -> list[Bucket]:
        self.calls += 1
        if self.error:
            raise self.error
        return _empty36()


@pytest.fixture
def reader():
    fake = FakeReader()
    monitoring._cache = None
    app.dependency_overrides[get_monitoring_reader] = lambda: fake
    yield fake
    monitoring._cache = None


def test_server_status_route_shape(client, world, reader):
    response = client.get("/admin/server-status", headers=ADMIN_HEADERS)

    assert response.status_code == 200
    body = response.json()
    assert set(body) == {"checked_at", "bucket_minutes", "buckets", "now", "anomalies"}
    assert body["bucket_minutes"] == 5
    assert len(body["buckets"]) == 36
    assert set(body["buckets"][0]) == {"start", "requests", "errors_5xx", "p50_ms", "p95_ms", "instances"}
    assert body["anomalies"] == []


@pytest.mark.parametrize("error", [
    httpx.HTTPStatusError("x", request=httpx.Request("GET", "https://g"), response=httpx.Response(403)),
    httpx.TimeoutException("x"),
])
def test_monitoring_failure_is_503(client, world, reader, error):
    reader.error = error

    response = client.get("/admin/server-status", headers=ADMIN_HEADERS)

    assert response.status_code == 503
    assert response.json()["detail"] == "잠시 후 다시 시도해 주세요"


def _real_reader(handler, token=_fake_token) -> MonitoringReader:
    return MonitoringReader(httpx.AsyncClient(transport=httpx.MockTransport(handler)), "test-project", token)


async def _broken_token() -> str:
    raise google.auth.exceptions.RefreshError("x")


@pytest.mark.parametrize("reader_under_test", [
    pytest.param(lambda: _real_reader(lambda r: httpx.Response(200, text="<html>")), id="200-not-json"),
    pytest.param(lambda: _real_reader(lambda r: httpx.Response(200, json={"timeSeries": [{"points": [{"value": {}}]}]})),
                 id="200-point-without-interval"),
    pytest.param(lambda: _real_reader(lambda r: httpx.Response(200, json=[])), id="200-json-array"),
    # world.now(10-18 12:00 서울 = 03:00Z) 창의 마지막 칸 끝 — 창 안 점이라야 칸 합치기의 round() 까지 간다.
    pytest.param(lambda: _real_reader(lambda r: httpx.Response(200, json={"timeSeries": [
        {"points": [{"interval": {"endTime": "2026-10-18T03:00:00Z"}, "value": {"doubleValue": "NaN"}}]}]})),
        id="200-nan-value"),
    pytest.param(lambda: _real_reader(lambda r: httpx.Response(200, json={}), _broken_token), id="token-auth-error"),
])
def test_unexpected_google_answer_is_503_and_not_cached(client, world, reader, reader_under_test):
    app.dependency_overrides[get_monitoring_reader] = reader_under_test

    response = client.get("/admin/server-status", headers=ADMIN_HEADERS)

    assert response.status_code == 503
    assert response.json()["detail"] == "잠시 후 다시 시도해 주세요"
    assert monitoring._cache is None


def test_our_own_bug_is_not_hidden_as_503(client, world, reader):
    # 우리 코드 실수(KeyError 등)는 "구글 못 읽음" 503 으로 가리지 않는다. TestClient 는 서버 예외를 그대로 올린다(운영은 500).
    reader.error = KeyError("our-bug")

    with pytest.raises(KeyError):
        client.get("/admin/server-status", headers=ADMIN_HEADERS)
    assert monitoring._cache is None


def test_cached_within_60s(client, world, reader):
    start = world.now
    client.get("/admin/server-status", headers=ADMIN_HEADERS)
    world.now = start + timedelta(seconds=59)
    client.get("/admin/server-status", headers=ADMIN_HEADERS)
    assert reader.calls == 1

    world.now = start + timedelta(seconds=61)
    client.get("/admin/server-status", headers=ADMIN_HEADERS)
    assert reader.calls == 2


def test_failed_read_is_not_cached(client, world, reader):
    reader.error = httpx.TimeoutException("x")
    assert client.get("/admin/server-status", headers=ADMIN_HEADERS).status_code == 503

    reader.error = None
    assert client.get("/admin/server-status", headers=ADMIN_HEADERS).status_code == 200
    assert reader.calls == 2


@pytest.mark.parametrize(("who", "headers", "status", "detail"), [
    ("로그인 안 함", {}, 401, None),
    ("2단계 전", bearer(sub=ADMIN, aal="aal1"), 403, "mfa_required"),
    ("관리자 아님", bearer(sub=STRANGER, aal="aal2"), 403, "not_admin"),
])
def test_server_status_needs_admin(client, world, reader, who, headers, status, detail):
    if who == "관리자 아님":
        world.caller = STRANGER

    response = client.get("/admin/server-status", headers=headers)

    assert response.status_code == status
    if detail:
        assert response.json()["detail"] == detail
    assert reader.calls == 0


# --- 실패 로그(11-18 운영: 로그에 구글 응답 코드가 안 보였다) -------------------------------------------------------

def test_google_status_code_is_logged(client, world, reader, caplog):
    reader.error = httpx.HTTPStatusError(
        "Client error '429' for url 'https://g/secret-path?token=t'", request=httpx.Request("GET", "https://g/secret-path?token=t"), response=httpx.Response(429, text="google-body"))

    with caplog.at_level("WARNING", logger="app.admin.server_status"):
        assert client.get("/admin/server-status", headers=ADMIN_HEADERS).status_code == 503

    assert "HTTPStatusError 429" in caplog.text
    assert "secret-path" not in caplog.text and "google-body" not in caplog.text
