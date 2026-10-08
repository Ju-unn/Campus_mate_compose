"""계정: 탈퇴(B3) · 내 카카오톡 아이디(B5, 16e-1) · 계정 화면(16e)."""
import logging

import httpx
from fastapi import APIRouter, Depends, Header, HTTPException

from app.account.repository import AccountRepository, SupabaseAdmin
from app.account.social_unlink import unlink_kakao
from app.chat.repository import ChatRepository
from app.core import errors
from app.core.deps import Caller, get_caller, get_verified_caller
from app.signup_policy import IDENTITY_KEY_VERSION

logger = logging.getLogger(__name__)

router = APIRouter()


@router.post("/account/withdraw")
async def withdraw(caller: Caller = Depends(get_caller),
                   authorization: str | None = Header(default=None)) -> dict:
    """탈퇴. 로그인만 본다 — 정지 · 학생증 미인증인 사람도 나갈 수 있어야 한다(정지 중 탈퇴 = 무기한 제한).

    ① 학교 메일 인증 기록(school_email_claims)의 해시 · 키 버전 ② DB 함수 한 번(상태 + 재가입 제한).
    해시는 auth 의 email 이 아니라 인증된 학교 메일의 것이다(카카오는 계정 메일이 없다). 기록이 없으면(학교 메일 인증 전)
    null 을 넘겨 재가입 제한을 남기지 않는다. 기록을 못 읽으면 503 으로 멈춘다 — null 로 탈퇴시키면 제한을 잃는다.
    ② 가 실패하면 500 이고 다시 부르면 된다.
    ③ 뒤 넷은 각각 best-effort 다. 남은 것은 30일 정리 배치가 auth 사용자째 지운다.
    카카오 연결 끊기는 로그아웃 앞이다 — 로그아웃 뒤에는 그 토큰으로 회원번호(/user)를 못 읽을 수 있다."""
    settings, client, profile_id = caller
    accounts = AccountRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    admin = SupabaseAdmin(settings, client)

    try:
        claim = await accounts.fetch_school_email_claim(profile_id)
    except httpx.HTTPError as exc:
        logger.warning("탈퇴 전 학교 메일 인증 기록 읽기 실패 → 503 %s", type(exc).__name__)
        raise HTTPException(status_code=503, detail=errors.AUTH_UNAVAILABLE)
    if claim is None:
        await accounts.withdraw(profile_id, None, IDENTITY_KEY_VERSION)
    else:
        await accounts.withdraw(profile_id, claim["school_email_hmac"], claim["key_version"])

    # 상태가 바뀐 뒤에는 다시 부르면 401 이라, 여기서 500 을 내 봐야 재시도가 안 된다 — 실패는 로그만 남긴다.
    steps = (
        ("push_tokens", lambda: accounts.delete_push_tokens(profile_id)),
        ("student_id_files", lambda: admin.empty_folder("student-id-temp", profile_id)),
        ("kakao_unlink", lambda: unlink_kakao(settings, client, authorization)),
        ("logout", lambda: admin.logout_everywhere(authorization)),
    )
    for name, step in steps:
        try:
            await step()
        except Exception:
            logger.warning("탈퇴 뒤 정리 실패 step=%s profile=%s", name, profile_id)
    return {"ok": True}


@router.get("/account")
async def get_my_account(caller: Caller = Depends(get_verified_caller)) -> dict:
    """16e 계정 화면. 실명은 본인에게 가는 이 응답에만 싣고 로그에 찍지 않는다(DESIGN §9 16e · ERD §11-2).
    이메일은 앱이 자기 세션에서 읽는다. 인증 상태는 싣지 않는다 — 관문을 지난 사람만 닿으니 늘 '인증 완료'다."""
    settings, client, profile_id = caller
    accounts = AccountRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    profile = await accounts.fetch_account(profile_id)
    private = await accounts.fetch_private(profile_id)
    return {
        "real_name": private.get("real_name"),
        "birth_year": profile["birth_year"],
        "university": profile["universities"]["name"],
        "joined_at": profile["created_at"],
        "kakao_id": private.get("kakao_id"),
    }


@router.get("/account/kakao-id")
async def get_my_kakao_id(caller: Caller = Depends(get_verified_caller)) -> dict:
    """내 카카오톡 아이디(16e-1). 앱은 profile_private 를 직접 읽지 못한다(ERD §11-20)."""
    settings, client, profile_id = caller
    repo = ChatRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    return {"kakao_id": await repo.fetch_kakao_id(profile_id)}
