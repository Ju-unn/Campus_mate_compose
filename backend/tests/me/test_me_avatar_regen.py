"""15b 아바타 다시 만들기 등록(계획서 2-3). 워커 쪽은 test_avatar_async.py 가 본다."""
import httpx

from tests.profile_onboarding.test_avatar_async import (  # noqa: F401 — autouse 픽스처도 같이 가져온다
    AUTH_HEADERS, _client, _Fake, _failed, _settings, fake_google_credentials, overrides,
)
from app.core.deps import get_settings
from app.main import app


class _MeFake(_Fake):
    def __init__(self, balance: int | None = 0, **kwargs):
        super().__init__(**kwargs)
        self.balance = balance

    def __call__(self, request):
        if "/rest/v1/entitlements" in str(request.url):
            self.requests.append(request)
            return httpx.Response(200, json=[] if self.balance is None else [{"heart_balance": self.balance}])
        return super().__call__(request)


def _regen(fake: _Fake) -> httpx.Response:
    return _client(fake).post("/me/avatar/regenerate", headers=AUTH_HEADERS)


def _ready(count: int) -> list[dict]:
    return [{"id": f"r{i}"} for i in range(count)]


def test_free_regeneration_is_queued_even_with_zero_hearts():
    fake = _MeFake(balance=0, ready_rows=_ready(1))

    response = _regen(fake)

    assert response.status_code == 202
    assert response.json() == {"status": "pending", "avatar_url": None, "compensation_hearts": None}
    assert len(fake.enqueued) == 1
    # 여기서는 하트를 빼지 않는다(T2).
    assert fake.granted_hearts == []


def test_paid_regeneration_is_queued_when_the_balance_covers_it():
    fake = _MeFake(balance=10, ready_rows=_ready(2))

    assert _regen(fake).status_code == 202
    assert len(fake.enqueued) == 1
    assert fake.granted_hearts == []


def test_paid_regeneration_is_refused_before_any_row_when_hearts_are_short():
    fake = _MeFake(balance=9, ready_rows=_ready(2))

    response = _regen(fake)

    assert response.status_code == 402
    assert response.json() == {"detail": "하트가 모자라요"}
    assert fake.inserted_avatars == []
    assert fake.enqueued == []


def test_missing_entitlements_row_counts_as_zero_hearts():
    assert _regen(_MeFake(balance=None, ready_rows=_ready(2))).status_code == 402


def test_regeneration_needs_a_first_avatar():
    fake = _MeFake(balance=100, ready_rows=[])

    response = _regen(fake)

    assert response.status_code == 409
    assert response.json() == {"detail": "아바타를 먼저 만들어 주세요"}
    assert fake.inserted_avatars == []


def test_regeneration_needs_the_source_photo():
    response = _regen(_MeFake(balance=0, ready_rows=_ready(1), source_path=None))

    assert response.status_code == 409
    assert response.json() == {"detail": "아바타 원본 사진을 먼저 골라 주세요"}


def test_regeneration_never_pays_the_five_failure_compensation():
    """온보딩 POST 의 5회 보상 출구는 옮겨 오지 않는다(T3) — 실패가 5번 쌓여도 그냥 등록한다."""
    fake = _MeFake(balance=0, ready_rows=_ready(1), attempt_rows=_failed(5))

    assert _regen(fake).status_code == 202
    assert fake.granted_hearts == []
    assert [row["status"] for row in fake.inserted_avatars] == ["pending"]


def test_pressing_twice_gives_the_same_202_without_a_second_task():
    fake = _MeFake(balance=0, ready_rows=_ready(1), pending_conflict=True)

    assert _regen(fake).status_code == 202
    assert fake.enqueued == []


def test_stale_pending_rows_are_cleaned_before_inserting():
    fake = _MeFake(balance=0, ready_rows=_ready(1), stale_rows=[{"id": "old"}])

    _regen(fake)

    cleanup = fake.calls("PATCH", "created_at=lt.")
    assert len(cleanup) == 1
    assert fake.requests.index(cleanup[0]) < fake.requests.index(fake.calls("POST", "/rest/v1/profile_avatars")[0])


def test_queue_failure_removes_the_row_and_returns_502():
    fake = _MeFake(balance=0, ready_rows=_ready(1), enqueue_status=500)

    response = _regen(fake)

    assert response.status_code == 502
    assert len(fake.calls("DELETE", "/rest/v1/profile_avatars")) == 1


def test_returns_503_before_anything_when_the_queue_is_not_configured():
    app.dependency_overrides[get_settings] = lambda: _settings(avatar_tasks_queue="")
    fake = _MeFake(balance=0, ready_rows=_ready(1))

    assert _regen(fake).status_code == 503
    assert fake.inserted_avatars == []


def test_rejects_missing_login():
    assert _client(_MeFake(ready_rows=_ready(1))).post("/me/avatar/regenerate").status_code == 401
