"""계정: 탈퇴(B3) · 내 카카오톡 아이디(B5, 16e-1) · 계정 화면(16e)."""
import logging
from datetime import datetime

import httpx
from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel

from app.account.repository import AccountRepository, SupabaseAdmin
from app.account.social_unlink import exchange_apple_code, revoke_apple_token, unlink_kakao
from app.chat.repository import ChatRepository
from app.core import errors
from app.core.deps import Caller, get_caller, get_now, get_verified_caller
from app.graduate_verification.repository import GraduateRequestRepository
from app.graduate_verification.retention import delete_photo
from app.graduate_verification.storage import GraduateCertStorage
from app.signup_policy import IDENTITY_KEY_VERSION

logger = logging.getLogger(__name__)

router = APIRouter()


class WithdrawRequest(BaseModel):
    # 애플로 가입한 사람만 앱이 탈퇴 직전 애플 창을 한 번 더 띄워 받아 온다(일회용 · 5분). 토큰 철회에만 쓰고 저장하지 않는다.
    # 없으면(카카오 · 구글 · 애플 창을 닫은 사람 · 본문 없이 부르는 옛 앱과 하네스) 철회만 건너뛴다.
    apple_authorization_code: str | None = None


@router.post("/account/withdraw")
async def withdraw(body: WithdrawRequest | None = None,
                   caller: Caller = Depends(get_caller),
                   now: datetime = Depends(get_now),
                   authorization: str | None = Header(default=None)) -> dict:
    """탈퇴. 로그인만 본다 — 정지 · 학생증 미인증인 사람도 나갈 수 있어야 한다(정지 중 탈퇴 = 무기한 제한).

    ① 학교 메일 인증 기록(school_email_claims)의 해시 · 키 버전 — 없으면 졸업생 인증 때 관리자가 넣은 학번 해시 ② DB 함수 한 번(상태 + 재가입 제한).
    해시는 auth 의 email 이 아니라 인증된 학교 메일의 것이다(카카오는 계정 메일이 없다). 둘 다 없으면(인증 전 · 학번 없이 승인된 졸업생)
    null 을 넘겨 재가입 제한을 남기지 않는다. 기록을 못 읽으면 503 으로 멈춘다 — null 로 탈퇴시키면 제한을 잃는다.
    ② 가 실패하면 500 이고 다시 부르면 된다.
    ③ 뒤 정리 단계(steps)는 각각 best-effort 다. 남은 것은 30일 정리 배치가 auth 사용자째 지운다.
    카카오 연결 끊기는 로그아웃 앞이다 — 로그아웃 뒤에는 그 토큰으로 회원번호(/user)를 못 읽을 수 있다.
    애플 토큰 철회(App Store 5.1.1(v))도 같은 정책이다 — 실패하거나 코드가 없어도 탈퇴는 그대로 끝난다."""
    settings, client, profile_id = caller
    accounts = AccountRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    admin = SupabaseAdmin(settings, client)

    try:
        rejoin_hash, key_version = await _rejoin_hash(accounts, profile_id)
    except httpx.HTTPError as exc:
        logger.warning("탈퇴 전 재가입 제한 해시 읽기 실패 → 503 %s", type(exc).__name__)
        raise HTTPException(status_code=503, detail=errors.AUTH_UNAVAILABLE)
    await accounts.withdraw(profile_id, rejoin_hash, key_version)

    # 애플은 두 단계다 — 코드 교환이 준 refresh_token 을 철회 단계가 쓴다. 교환이 실패하면 철회는 건너뛴다.
    apple_refresh_token: str | None = None

    async def exchange_apple() -> None:
        nonlocal apple_refresh_token
        apple_refresh_token = await exchange_apple_code(settings, client, body and body.apple_authorization_code)

    # 상태가 바뀐 뒤에는 다시 부르면 401 이라, 여기서 500 을 내 봐야 재시도가 안 된다 — 실패는 로그만 남긴다.
    graduate_repo = GraduateRequestRepository(settings.postgrest_url, settings.supabase_service_role_key, client)

    async def close_graduate_request() -> None:
        # 심사 중이던 졸업생 신청을 닫고(평문 비움) 사진을 지운다. 대기가 없으면 아무 일도 하지 않는다.
        cancelled = await graduate_repo.cancel_pending(profile_id, "account_withdrawn", now)
        if cancelled is not None:
            storage = GraduateCertStorage(settings.storage_url, settings.supabase_service_role_key, client)
            await delete_photo(graduate_repo, storage, cancelled["id"], cancelled["photo_path"])

    steps = (
        ("push_tokens", lambda: accounts.delete_push_tokens(profile_id)),
        ("student_id_files", lambda: admin.empty_folder("student-id-temp", profile_id)),
        ("graduate_request", close_graduate_request),
        ("graduate_files", lambda: admin.empty_folder("graduate-cert-temp", profile_id)),
        ("kakao_unlink", lambda: unlink_kakao(settings, client, authorization)),
        ("apple_token_exchange", exchange_apple),
        ("apple_revoke", lambda: revoke_apple_token(settings, client, apple_refresh_token)),
        ("logout", lambda: admin.logout_everywhere(authorization)),
    )
    for name, step in steps:
        try:
            await step()
        except Exception:
            logger.warning("탈퇴 뒤 정리 실패 step=%s profile=%s", name, profile_id)
    return {"ok": True}


async def _rejoin_hash(accounts: AccountRepository, profile_id) -> tuple[str | None, int]:
    """탈퇴 재가입 제한에 쓸 (해시, 키 버전). 학교 메일 인증 기록이 먼저고, 없으면 졸업생 학번 해시, 둘 다 없으면 (None, 현재 버전)."""
    claim = await accounts.fetch_school_email_claim(profile_id)
    if claim is not None:
        return claim["school_email_hmac"], claim["key_version"]
    graduate = await accounts.fetch_graduate_claim(profile_id)
    if graduate is not None:
        return graduate["student_hmac"], graduate["key_version"]
    return None, IDENTITY_KEY_VERSION


@router.get("/account")
async def get_my_account(caller: Caller = Depends(get_verified_caller)) -> dict:
    """16e 계정 화면. 실명은 싣지 않는다(학생증 제거 10-17) — 옛 계정에 암호문이 남아 있어도 읽지 않는다.
    옛 앱은 real_name 을 `as String?` 로 읽어 칸이 없으면 null 로 본다(frontend account_repository.dart).
    이메일은 앱이 자기 세션에서 읽는다. 인증 상태는 싣지 않는다 — 관문을 지난 사람만 닿으니 늘 '인증 완료'다."""
    settings, client, profile_id = caller
    accounts = AccountRepository(
        settings.postgrest_url, settings.supabase_service_role_key, client, encryption_key=settings.phone_encryption_key
    )
    profile = await accounts.fetch_account(profile_id)
    private = await accounts.fetch_private(profile_id)
    return {
        "birth_year": profile["birth_year"],
        "university": profile["universities"]["name"],
        "joined_at": profile["created_at"],
        "kakao_id": private.get("kakao_id"),
    }


@router.get("/account/kakao-id")
async def get_my_kakao_id(caller: Caller = Depends(get_verified_caller)) -> dict:
    """내 카카오톡 아이디(16e-1). 앱은 profile_private 를 직접 읽지 못한다(ERD §11-20)."""
    settings, client, profile_id = caller
    repo = ChatRepository(
        settings.postgrest_url, settings.supabase_service_role_key, client, encryption_key=settings.phone_encryption_key
    )
    return {"kakao_id": await repo.fetch_kakao_id(profile_id)}
