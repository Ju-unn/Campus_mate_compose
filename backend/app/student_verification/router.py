from fastapi import APIRouter, Depends, HTTPException

from app.consents.policy import consent_state
from app.consents.repository import ConsentRepository
from app.core import errors
from app.core.deps import Caller, get_caller
from app.graduate_verification.applicant_router import router as graduate_applicant_router
from app.graduate_verification.repository import GraduateRequestRepository, attempts_used
from app.graduate_verification.messages import MAX_ATTEMPTS
from app.graduate_verification.settings import graduate_enabled
from app.student_verification.current_user import reject_suspended, require_school_email
from app.student_verification.repository import StudentVerificationRepository
from app.student_verification.schemas import GraduateState, SchoolInfoRequest, VerificationStatusResponse

router = APIRouter()
# 졸업생 인증(졸업증명서) 신청자 API 는 이 라우터 밑에 붙인다 — main.py(공유 파일)를 건드리지 않는 우회.
router.include_router(graduate_applicant_router)

# 학생증 제출(POST /student-verification)은 없앴다(학생증 제거 10-17, 설계 결정 9). 옛 앱이 부르면 404 다.
# OCR · 대조 · 사진 저장 모듈은 출시 후 정리(출시후_할일 1-1)까지 그대로 둔다.


@router.get("/me/verification-status")
async def fetch_verification_status(caller: Caller = Depends(get_caller)) -> VerificationStatusResponse:
    """앱이 다음 화면을 고르는 응답. 관문 순서는 정지 → 동의 → 학교 메일 → 학과와 학번 이다.

    정지(X-Account-Status 헤더)는 다른 API 가 알려 주고, 나머지 셋은 이 응답의 consent ·
    school_email_verified · has_school_info 가 그 순서로 맡는다. 로그인만 보는 문이라
    정지 · 동의 전 · 학교 메일 전에도 닿는다(그래야 안내 화면으로 간다).

    졸업생 인증 길(졸업증명서)은 새 칸 세 개가 맡는다: graduate_enabled(서버 플래그) · verification_method(고른 길) ·
    graduate(대기 · 반려 상태). 졸업생 신청 표는 플래그가 켜져 있고 졸업생 길을 고른 인증 전 사람만 읽는다.

    status 는 늘 "verified", reject_reason 은 늘 null 이다 — 옛 앱(빌드 15 · TF 16 · vc8)이 status 가 verified 가
    아니면 학생증 화면으로 보내기 때문이다. DB 값은 읽지도 바꾸지도 않는다. 옛 앱이 사라지면 두 칸을 지운다(출시후 1-7)."""
    settings, client, profile_id = caller
    repo = StudentVerificationRepository(settings.postgrest_url, settings.supabase_service_role_key, client)

    gate = await repo.fetch_gate_status(profile_id)
    consents = ConsentRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    verified = gate.get("school_email_verified_at") is not None
    method = gate.get("verification_method")
    enabled = graduate_enabled()
    graduate = None
    if enabled and not verified and method == "graduate_certificate":
        graduate = _graduate_state(await GraduateRequestRepository(
            settings.postgrest_url, settings.supabase_service_role_key, client).fetch_history(profile_id))
    return VerificationStatusResponse(
        status="verified",
        has_school_info=gate["department"] is not None,
        reject_reason=None,
        consent=consent_state(await consents.fetch_rows(profile_id)),
        school_email_verified=verified,
        graduate_enabled=enabled,
        verification_method=method,
        graduate=graduate,
    )


def _graduate_state(history: list[dict]) -> GraduateState | None:
    """가장 최근 신청이 대기 · 반려일 때만 상태를 만든다. 취소 · 신청 없음은 null(앱은 신청 폼을 보인다)."""
    if not history or history[0]["status"] not in ("pending", "rejected"):
        return None
    latest = history[0]
    return GraduateState(
        state=latest["status"], reject_reason=latest["reason"],
        attempts_left=max(0, MAX_ATTEMPTS - attempts_used(history)), submitted_at=latest["created_at"],
    )


@router.post("/school-info")
async def save_school_info(body: SchoolInfoRequest, caller: Caller = Depends(get_caller)) -> dict[str, bool]:
    settings, client, profile_id = caller
    repo = StudentVerificationRepository(settings.postgrest_url, settings.supabase_service_role_key, client)

    gate = await repo.fetch_gate_status(profile_id)
    # 결정 9(B6, 10-01): 정지 계정은 학과 · 학번을 바꾸지 못한다. 인증 상태 조회 · 동의 · 탈퇴는 열어 둔다.
    reject_suspended(gate.get("status"))
    require_school_email(gate)
    if not body.has_valid_student_number():
        raise HTTPException(status_code=422, detail=errors.STUDENT_NUMBER_INVALID)

    await repo.save_school_info(profile_id, body.department, body.student_number)
    return {"ok": True}
