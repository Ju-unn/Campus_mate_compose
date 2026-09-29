"""Cloud Scheduler 배치의 신원 확인(core/batch_auth.py `verify_oidc_token`, 아바타 워커와 같은 함수).

조각 6 OIDC 전환 5단계에서 옛 `X-Batch-Secret` 문을 지웠다 — 구글 ID 토큰만 통과한다. 라우터
테스트(cards/test_batch_router.py · chat/test_chat_batch.py · account/test_cleanup_batch.py)는
세 엔드포인트가 토큰으로 열리는지만 보고, 조합은 여기서 덮는다.
"""
import httpx
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

import app.core.batch_auth as batch_auth
from app.core.batch_auth import verify_oidc_token
from app.core.deps import get_client, get_settings
from app.main import app
from app.settings import Settings

AUDIENCE = "https://campus-mate-backend.example.run.app"
SCHEDULER = "campus-mate-scheduler@example.iam.gserviceaccount.com"


def _google_signs(
    monkeypatch: pytest.MonkeyPatch, *, issued_for: str = AUDIENCE,
    email: str = SCHEDULER, email_verified: bool = True,
) -> None:
    """구글 서명 확인만 가짜로 한다 — 토큰이 `issued_for` 앞으로 발급됐다고 치고, 서버가 다른 audience 를
    넘기면 진짜 라이브러리처럼 ValueError 를 낸다. 발급자 확인은 진짜 코드가 그대로 한다."""
    def fake_verify(token, request, audience):
        if audience != issued_for:
            raise ValueError("Token has wrong audience")
        return {"email": email, "email_verified": email_verified}

    monkeypatch.setattr(batch_auth.id_token, "verify_oauth2_token", fake_verify)


async def _call(
    *, authorization: str | None = "Bearer id-token",
    audience: str = AUDIENCE, service_account_email: str = SCHEDULER,
) -> None:
    await verify_oidc_token(
        authorization, audience=audience, service_account_email=service_account_email
    )


async def _rejected(**kwargs) -> int:
    with pytest.raises(HTTPException) as raised:
        await _call(**kwargs)
    return raised.value.status_code


async def test_a_scheduler_id_token_opens_the_door(monkeypatch):
    _google_signs(monkeypatch)

    await _call()  # 401 이면 여기서 터진다


async def test_a_caller_without_a_token_is_turned_away():
    assert await _rejected(authorization=None) == 401


@pytest.mark.parametrize("path", ["/batch/daily-cards", "/batch/chat-gate", "/batch/cleanup"])
def test_the_old_shared_key_opens_no_batch_door(monkeypatch, path):
    """공유 열쇠를 지운 뒤 첫 배포에는 서비스에 옛 `CARD_BATCH_SECRET` 참조가 남는다(DEPLOY.md §4-3).
    그 env 로 설정을 만들어도 옛 헤더로는 어느 배치도 열리지 않고, 저장소는 한 번도 불리지 않는다."""
    monkeypatch.setenv("CARD_BATCH_SECRET", "right")
    called = []
    http = httpx.AsyncClient(transport=httpx.MockTransport(
        lambda request: called.append(request) or httpx.Response(200, json=[])
    ))
    # 운영처럼 env 에서 그대로 읽는다(람다로 감싸야 FastAPI 가 필드를 쿼리로 보지 않는다).
    app.dependency_overrides[get_settings] = lambda: Settings()
    app.dependency_overrides[get_client] = lambda: http
    try:
        response = TestClient(app, raise_server_exceptions=False).post(
            path, headers={"X-Batch-Secret": "right"}
        )
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 401
    assert called == []


async def test_a_token_minted_for_a_different_audience_is_turned_away(monkeypatch):
    """job 에 `--oidc-token-audience` 를 빠뜨리면 구글이 job 의 전체 URL(경로 포함)로 토큰을 만든다 —
    서버 설정(경로 없는 서비스 URL)과 어긋나 401 이다(DEPLOY.md 가 audience 를 못 박는 이유)."""
    _google_signs(monkeypatch, issued_for=f"{AUDIENCE}/batch/daily-cards")

    assert await _rejected() == 401


async def test_a_token_from_another_service_account_is_turned_away(monkeypatch):
    """audience 만 보면 그 URL 을 아는 다른 계정도 들어온다 — 발급자까지 본다."""
    _google_signs(monkeypatch, email="someone-else@evil.iam.gserviceaccount.com")

    assert await _rejected() == 401


async def test_a_token_whose_email_is_not_verified_is_turned_away(monkeypatch):
    _google_signs(monkeypatch, email_verified=False)

    assert await _rejected() == 401


@pytest.mark.parametrize(
    "setting, issued_for",
    # 토큰은 각 경우에 서버가 넘기는 audience 그대로 발급됐다고 친다 — 서명 확인은 통과하는 토큰이다.
    [("audience", ""), ("service_account_email", AUDIENCE)],
)
async def test_an_unconfigured_oidc_setting_lets_no_token_in(monkeypatch, setting, issued_for):
    """env 를 빠뜨린 배포가 열린 문이 되지 않게 — 유효한 토큰이어도 401 이다."""
    _google_signs(monkeypatch, issued_for=issued_for)

    assert await _rejected(**{setting: ""}) == 401
