"""관리자가 사용자에게 하는 일: 하트 조정 · 전화/카톡 열람 · 앱 밖 탈퇴 대행(설계 10-18 §8-3, 화면 A5 의 대화상자들).

모두 사유가 필수다. 관리자 계정은 대상이 될 수 없다(404). 하트 조정과 탈퇴는 DB 함수 한 번(한 트랜잭션, 마이그레이션 20261018120000),
열람은 기록 한 줄을 **먼저** 남긴 뒤 복호화한다 — 기록이 실패하면 값을 읽지도 돌려주지도 않는다.
"""
import logging
from uuid import UUID

import httpx
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, StrictInt, field_validator

from app.account.repository import AccountRepository, SupabaseAdmin
from app.account.social_unlink import unlink_kakao_for_user
from app.admin.caller import AdminCaller, get_admin_caller
from app.admin.reason import Reason, ReasonBody
from app.admin.repository import ACCOUNT_WITHDRAWN, NOT_FOUND
from app.admin.request_ip import request_ip
from app.admin.user_repository import AdminUserRepository
from app.core import errors
from app.signup_policy import IDENTITY_KEY_VERSION

router = APIRouter(prefix="/users")
logger = logging.getLogger(__name__)

# 하트 조정 한 번의 상한(대장 결정 10-18). DB 함수 admin_adjust_hearts 의 c_max_adjust 와 같은 값 — DB 가 진짜 관문이고 여기는 빠른 422 다.
ADJUST_MAX = 1000


class HeartsBody(BaseModel):
    # 더하면 +, 빼면 −(잔액 이하만). 소수 · 문자열 · true 는 정수가 아니다.
    amount: StrictInt
    reason: Reason

    @field_validator("amount")
    @classmethod
    def _within_limit(cls, amount: int) -> int:
        if amount == 0 or abs(amount) > ADJUST_MAX:
            raise ValueError(f"amount must be a nonzero integer within ±{ADJUST_MAX}")
        return amount


def _repo(caller: AdminCaller) -> AdminUserRepository:
    # 열람만 복호화 키가 필요하다. 키는 JSON 본문으로만 DB 에 간다(URL 은 접근 로그에 남는다).
    return AdminUserRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client,
                               encryption_key=caller.settings.phone_encryption_key)


@router.post("/{user_id}/hearts")
async def adjust_hearts(
    user_id: UUID, body: HeartsBody, request: Request, caller: AdminCaller = Depends(get_admin_caller),
) -> dict:
    """하트 조정. 잔액이 모자라면 409 insufficient_hearts, 탈퇴 계정은 409 account_withdrawn, 없음 · 관리자 404."""
    return await _repo(caller).adjust_hearts(caller.admin_user_id, user_id, body.amount, body.reason, request_ip(request))


@router.post("/{user_id}/private")
async def view_private(
    user_id: UUID, body: ReasonBody, request: Request, caller: AdminCaller = Depends(get_admin_caller),
) -> JSONResponse:
    """전화 · 카톡 열람. 그 자리에서만 보여 주고(저장 · 캐시 없음) 작업 기록에는 "열람했다" 와 사유 · ip 만 남긴다."""
    repo = _repo(caller)
    status = await repo.fetch_profile_status(user_id)
    if status is None or await repo.is_admin(user_id):
        raise HTTPException(status_code=404, detail=NOT_FOUND)
    if status == "withdrawn":
        # 탈퇴 뒤에는 열람 사유가 없고 값은 30일 뒤 지워진다(대장 결정 6).
        raise HTTPException(status_code=409, detail=ACCOUNT_WITHDRAWN)
    await repo.record_action(caller.admin_user_id, "profile_private_view", target_type="profile", target_id=str(user_id),
                             reason=body.reason, ip=request_ip(request))
    return JSONResponse(await repo.read_private_contact(user_id),
                        headers={"Cache-Control": "no-store", "Pragma": "no-cache"})


# --- 탈퇴 대행 -----------------------------------------------------------------------

VERIFIED_BY_MAX = 200
# 화면에 알린다: 본인 토큰이 있어야 하는 정리는 대행할 수 없다.
NOT_DONE = ["apple_revoke", "logout_everywhere"]


class CloseAccountBody(BaseModel):
    reason: Reason
    # 제약 없이 받고 핸들러가 검사한다 — 기본 422 가 입력(메일 주소일 수 있다)을 되돌리지 않게.
    verified_by: str


def _verified_by(text: str) -> str:
    """본인 확인 방법(작업 기록 after 에 남는다). 메일 원문이 기록에 새지 않게 '@' 가 있으면 거절한다."""
    text = text.strip()
    if not text or len(text) > VERIFIED_BY_MAX or "@" in text:
        raise HTTPException(status_code=422, detail=errors.INVALID_INPUT)
    return text


async def _outside_cleanup(caller: AdminCaller, user_id: UUID) -> dict[str, str]:
    """탈퇴 뒤 바깥 정리. 각각 best-effort — 한 단계가 실패해도 다음 단계로 간다(앱 안 탈퇴와 같은 정리, account/router.py).
    로그에는 단계 이름과 profile 번호만(회원번호 · 키 · 메일은 남기지 않는다)."""
    settings, client = caller.settings, caller.client
    accounts = AccountRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    admin = SupabaseAdmin(settings, client)

    async def push_tokens() -> None:
        await accounts.delete_push_tokens(user_id)

    async def student_id_files() -> None:
        await admin.empty_folder("student-id-temp", user_id)

    async def kakao_unlink() -> bool:
        return await unlink_kakao_for_user(settings, client, user_id)

    results: dict[str, str] = {}
    for name, step in (("push_tokens", push_tokens), ("student_id_files", student_id_files), ("kakao_unlink", kakao_unlink)):
        try:
            outcome = await step()
        except Exception:
            logger.warning("관리자 탈퇴 대행 뒤 정리 실패 step=%s profile=%s", name, user_id)
            results[name] = "failed"
        else:
            results[name] = "skipped" if outcome is False else "ok"
    return results


@router.post("/{user_id}/close-account")
async def close_account(
    user_id: UUID, body: CloseAccountBody, request: Request, caller: AdminCaller = Depends(get_admin_caller),
) -> dict:
    """앱 밖 탈퇴 요청 대행. ① 학교 메일 인증 기록(재가입 제한 해시)을 읽고 ② DB 함수로 탈퇴 + 기록 ③ 바깥 정리 ④ 정리 결과를 별도 기록.
    ②가 바깥 호출보다 먼저다 — ③은 실패해도 200 이다(이미 탈퇴됐고 다시 부르면 409 라 재시도가 안 된다). ①을 못 읽으면 아무것도
    바꾸기 전에 503(해시 없이 탈퇴시키면 재가입 제한을 잃는다 — 앱 안 탈퇴와 같은 규칙)."""
    verified_by = _verified_by(body.verified_by)
    repo = _repo(caller)
    accounts = AccountRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)
    try:
        claim = await accounts.fetch_school_email_claim(user_id)
    except httpx.HTTPError as exc:
        logger.warning("탈퇴 대행 전 학교 메일 인증 기록 읽기 실패 → 503 %s", type(exc).__name__)
        raise HTTPException(status_code=503, detail=errors.AUTH_UNAVAILABLE)
    ip = request_ip(request)
    closed = await repo.close_account(
        caller.admin_user_id, user_id, None if claim is None else claim["school_email_hmac"],
        IDENTITY_KEY_VERSION if claim is None else claim["key_version"], body.reason, verified_by, ip)

    cleanup = await _outside_cleanup(caller, user_id)
    try:
        await repo.record_action(caller.admin_user_id, "account_close_cleanup", target_type="profile",
                                 target_id=str(user_id), after=cleanup, ip=ip)
    except Exception:
        # 이미 탈퇴됐다 — 응답을 500 으로 만들면 다시 눌러도 409 라 헛수고다. 결과는 응답으로 알려 준다.
        logger.warning("탈퇴 대행 정리 결과 기록 실패 profile=%s", user_id)
    return {**closed, "cleanup": cleanup, "not_done": NOT_DONE}
