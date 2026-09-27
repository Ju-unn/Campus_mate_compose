"""Cloud Scheduler 배치의 신원 확인(core/batch_auth.py `verify_batch_caller`).

조각 6 OIDC 전환 2단계 "둘 다 받기" — 옛 `X-Batch-Secret` 이 맞거나 **또는** 구글 ID 토큰이 검증되면
통과한다. 라우터 테스트(cards/test_batch_router.py · chat/test_chat_batch.py)는 두 엔드포인트가
이 함수를 부르는지만 보고, 조합은 여기서 덮는다.
"""
import pytest
from fastapi import HTTPException

import app.core.batch_auth as batch_auth
from app.core.batch_auth import verify_batch_caller

SECRET = "right"
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
    *, authorization: str | None = None, x_batch_secret: str | None = None,
    batch_secret: str = SECRET, audience: str = AUDIENCE, service_account_email: str = SCHEDULER,
) -> str:
    return await verify_batch_caller(
        authorization=authorization, x_batch_secret=x_batch_secret, batch_secret=batch_secret,
        audience=audience, service_account_email=service_account_email,
    )


async def _rejected(**kwargs) -> int:
    with pytest.raises(HTTPException) as raised:
        await _call(**kwargs)
    return raised.value.status_code


async def test_the_old_header_still_opens_the_door_during_the_switch():
    """job 을 OIDC 로 바꾸기 전에 이 서버가 먼저 배포된다 — 그 사이 옛 헤더가 막히면 배치가 전부 401 이다."""
    assert await _call(x_batch_secret=SECRET) == "secret"


async def test_a_scheduler_id_token_opens_the_door(monkeypatch):
    _google_signs(monkeypatch)

    assert await _call(authorization="Bearer id-token") == "oidc"


async def test_a_wrong_old_header_does_not_block_a_good_id_token(monkeypatch):
    """전환 중 job 에 헤더와 토큰이 같이 실려 올 수 있다 — 헤더가 낡았어도 토큰이 맞으면 들어온다."""
    _google_signs(monkeypatch)

    assert await _call(authorization="Bearer id-token", x_batch_secret="wrong") == "oidc"


async def test_a_caller_with_neither_is_turned_away():
    assert await _rejected() == 401


async def test_a_wrong_old_header_without_a_token_is_turned_away():
    assert await _rejected(x_batch_secret="wrong") == 401


async def test_a_non_ascii_old_header_is_turned_away_instead_of_crashing():
    """Starlette 는 헤더를 latin-1 로 풀어서 0x80 이상 바이트가 비ASCII 글자로 온다. str 끼리의
    compare_digest 는 그때 TypeError 를 내서 500 이 된다 — 틀린 헤더처럼 401 이어야 한다."""
    assert await _rejected(x_batch_secret="sécret") == 401


async def test_an_empty_secret_setting_never_matches_an_empty_header():
    """시크릿을 빼고 배포해도 빈 헤더가 빈 설정과 '같다' 로 통과하면 안 된다."""
    assert await _rejected(x_batch_secret="", batch_secret="") == 401


async def test_a_token_minted_for_a_different_audience_is_turned_away(monkeypatch):
    """job 에 `--oidc-token-audience` 를 빠뜨리면 구글이 job 의 전체 URL(경로 포함)로 토큰을 만든다 —
    서버 설정(경로 없는 서비스 URL)과 어긋나 401 이다(DEPLOY.md 가 audience 를 못 박는 이유)."""
    _google_signs(monkeypatch, issued_for=f"{AUDIENCE}/batch/daily-cards")

    assert await _rejected(authorization="Bearer id-token") == 401


async def test_a_token_from_another_service_account_is_turned_away(monkeypatch):
    """audience 만 보면 그 URL 을 아는 다른 계정도 들어온다 — 발급자까지 본다."""
    _google_signs(monkeypatch, email="someone-else@evil.iam.gserviceaccount.com")

    assert await _rejected(authorization="Bearer id-token") == 401


async def test_a_token_whose_email_is_not_verified_is_turned_away(monkeypatch):
    _google_signs(monkeypatch, email_verified=False)

    assert await _rejected(authorization="Bearer id-token") == 401


@pytest.mark.parametrize(
    "setting, issued_for",
    # 토큰은 각 경우에 서버가 넘기는 audience 그대로 발급됐다고 친다 — 서명 확인은 통과하는 토큰이다.
    [("audience", ""), ("service_account_email", AUDIENCE)],
)
async def test_an_unconfigured_oidc_setting_lets_no_token_in(monkeypatch, setting, issued_for):
    """env 를 빠뜨린 배포가 열린 문이 되지 않게 — 유효한 토큰이어도 401 이다(옛 헤더는 계속 된다)."""
    _google_signs(monkeypatch, issued_for=issued_for)

    assert await _rejected(authorization="Bearer id-token", **{setting: ""}) == 401
    assert await _call(x_batch_secret=SECRET, **{setting: ""}) == "secret"
