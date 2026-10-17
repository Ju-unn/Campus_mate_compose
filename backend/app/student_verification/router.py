from fastapi import APIRouter, Depends

from app.consents.policy import consent_state
from app.consents.repository import ConsentRepository
from app.core.deps import Caller, get_caller
from app.student_verification.current_user import reject_suspended, require_school_email
from app.student_verification.repository import StudentVerificationRepository
from app.student_verification.schemas import SchoolInfoRequest, VerificationStatusResponse

router = APIRouter()

# 학생증 제출(POST /student-verification)은 없앴다(학생증 제거 10-17, 설계 결정 9). 옛 앱이 부르면 404 다.
# OCR · 대조 · 사진 저장 모듈은 출시 후 정리(출시후_할일 1-1)까지 그대로 둔다.


@router.get("/me/verification-status")
async def fetch_verification_status(caller: Caller = Depends(get_caller)) -> VerificationStatusResponse:
    """앱이 다음 화면을 고르는 응답. 관문 순서는 정지 → 동의 → 학교 메일 → 학과와 학번 이다.

    정지(X-Account-Status 헤더)는 다른 API 가 알려 주고, 나머지 셋은 이 응답의 consent ·
    school_email_verified · has_school_info 가 그 순서로 맡는다. 로그인만 보는 문이라
    정지 · 동의 전 · 학교 메일 전에도 닿는다(그래야 안내 화면으로 간다).

    status 는 늘 "verified", reject_reason 은 늘 null 이다 — 옛 앱(빌드 15 · TF 16 · vc8)이 status 가 verified 가
    아니면 학생증 화면으로 보내기 때문이다. DB 값은 읽지도 바꾸지도 않는다. 옛 앱이 사라지면 두 칸을 지운다(출시후 1-7)."""
    settings, client, profile_id = caller
    repo = StudentVerificationRepository(settings.postgrest_url, settings.supabase_service_role_key, client)

    gate = await repo.fetch_gate_status(profile_id)
    consents = ConsentRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    return VerificationStatusResponse(
        status="verified",
        has_school_info=gate["department"] is not None,
        reject_reason=None,
        consent=consent_state(await consents.fetch_rows(profile_id)),
        school_email_verified=gate.get("school_email_verified_at") is not None,
    )


@router.post("/school-info")
async def save_school_info(body: SchoolInfoRequest, caller: Caller = Depends(get_caller)) -> dict[str, bool]:
    settings, client, profile_id = caller
    repo = StudentVerificationRepository(settings.postgrest_url, settings.supabase_service_role_key, client)

    gate = await repo.fetch_gate_status(profile_id)
    # 결정 9(B6, 10-01): 정지 계정은 학과 · 학번을 바꾸지 못한다. 인증 상태 조회 · 동의 · 탈퇴는 열어 둔다.
    reject_suspended(gate.get("status"))
    require_school_email(gate)

    await repo.save_school_info(profile_id, body.department, body.student_number)
    return {"ok": True}
