"""계정: 탈퇴(B3) · 내 카카오톡 아이디(B5, 16e-1)."""
import logging

from fastapi import APIRouter, Depends, Header

from app.account.repository import AccountRepository, SupabaseAdmin
from app.chat.repository import ChatRepository
from app.core.deps import Caller, get_caller, get_verified_caller
from app.signup_policy import IDENTITY_KEY_VERSION, hash_email

logger = logging.getLogger(__name__)

router = APIRouter()


@router.post("/account/withdraw")
async def withdraw(caller: Caller = Depends(get_caller),
                   authorization: str | None = Header(default=None)) -> dict:
    """탈퇴. 로그인만 본다 — 정지 · 학생증 미인증인 사람도 나갈 수 있어야 한다(정지 중 탈퇴 = 무기한 제한).

    ① 이메일 → HMAC ② DB 함수 한 번(상태 + 재가입 제한). 여기까지 실패하면 500 이고 다시 부르면 된다.
    ③ 뒤 셋은 각각 best-effort 다. 남은 것은 30일 정리 배치가 auth 사용자째 지운다."""
    settings, client, profile_id = caller
    accounts = AccountRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    admin = SupabaseAdmin(settings, client)

    email = await admin.fetch_email(profile_id)
    await accounts.withdraw(profile_id, hash_email(settings.identity_hmac_key, email), IDENTITY_KEY_VERSION)

    # 상태가 바뀐 뒤에는 다시 부르면 401 이라, 여기서 500 을 내 봐야 재시도가 안 된다 — 실패는 로그만 남긴다.
    steps = (
        ("push_tokens", lambda: accounts.delete_push_tokens(profile_id)),
        ("student_id_files", lambda: admin.empty_folder("student-id-temp", profile_id)),
        ("logout", lambda: admin.logout_everywhere(authorization)),
    )
    for name, step in steps:
        try:
            await step()
        except Exception:
            logger.warning("탈퇴 뒤 정리 실패 step=%s profile=%s", name, profile_id)
    return {"ok": True}


@router.get("/account/kakao-id")
async def get_my_kakao_id(caller: Caller = Depends(get_verified_caller)) -> dict:
    """내 카카오톡 아이디(16e-1). 앱은 profile_private 를 직접 읽지 못한다(ERD §11-20)."""
    settings, client, profile_id = caller
    repo = ChatRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    return {"kakao_id": await repo.fetch_kakao_id(profile_id)}
