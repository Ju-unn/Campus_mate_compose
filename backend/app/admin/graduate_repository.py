"""관리자 졸업생 인증 검수의 읽기 · 승인/반려 DB 함수 호출. 학교 메일 claims · 재가입 제한은 **읽기만** 한다(쓰기 없음).

AdminRepository 를 이어받아 DB 함수 오류 약속(42501 · CM404 · CM409 · 22023)을 HTTP 로 바꾸는 _rpc 를 그대로 쓴다."""
from uuid import UUID

from app.admin.repository import ALREADY_REVIEWED, AdminRepository
from app.signup_policy import bytea_literal

_TABLE = "graduate_verification_requests"
# 신청자의 프로필(닉네임 · 학교 이름 · 탈퇴 여부)과 같은 사람의 신청들(순번 attempt_no)을 읽기 한 번에 임베드한다.
# 이메일 · 전화 · 카톡 아이디 같은 칸은 고르지 않는다. 평문 칸은 목록에 싣지 않는다.
_SIBLINGS = ("profile:profiles(status,nickname,universities(name),"
             "all_requests:graduate_verification_requests(id,created_at))")
_LIST_SELECT = f"id,profile_id,status,reason,created_at,decided_at,{_SIBLINGS}"
_ONE_SELECT = ("id,profile_id,status,reason,created_at,decided_at,photo_path,ocr_state,ocr_document_number,"
               f"ocr_school_text,previous_school_email,document_hmac,{_SIBLINGS}")
# DB 함수가 CM409 의 message 로 알려 주는 충돌 이유 — 서버는 글자 그대로 detail 로 보낸다.
CONFLICTS = {code: code for code in ("already_reviewed", "already_verified", "account_withdrawn", "document_reused",
                                     "student_reused", "rejoin_blocked")}


class GraduateAdminRepository(AdminRepository):

    async def list_requests(self, status: str, limit: int) -> list[dict]:
        """오래된 순(먼저 낸 사람부터 본다)."""
        return await self._rows(_TABLE, {
            "select": _LIST_SELECT, "status": f"eq.{status}", "order": "created_at.asc", "limit": str(limit),
        })

    async def fetch_request(self, request_id: UUID) -> dict | None:
        rows = await self._rows(_TABLE, {"select": _ONE_SELECT, "id": f"eq.{request_id}"})
        return rows[0] if rows else None

    async def fetch_history(self, profile_id: str, exclude_id: str, limit: int = 5) -> list[dict]:
        """같은 사람의 다른 신청(최근 순) — 결정 · 사유 · 시각만. 사진 · 평문은 이미 없다."""
        return await self._rows(_TABLE, {
            "select": "status,reason,decided_at", "profile_id": f"eq.{profile_id}", "id": f"neq.{exclude_id}",
            "order": "created_at.desc", "limit": str(limit),
        })

    async def find_claim_owner(self, email_hmac: bytes) -> dict | None:
        """그 학교 메일 해시를 지금 쓰는 계정(profile_id · profiles.status). 읽기 전용 — 선점하지 않는다."""
        rows = await self._rows("school_email_claims", {
            "school_email_hmac": f"eq.{bytea_literal(email_hmac)}", "select": "profile_id,profiles(status)", "limit": "1",
        })
        return rows[0] if rows else None

    async def find_approved_with_document(self, document_hmac: str, exclude_profile: str) -> str | None:
        """같은 문서 번호로 이미 승인된 다른 사람의 profile_id. document_hmac 은 DB 에서 읽은 bytea 리터럴 그대로다."""
        rows = await self._rows(_TABLE, {
            "document_hmac": f"eq.{document_hmac}", "status": "eq.approved", "profile_id": f"neq.{exclude_profile}",
            "select": "profile_id", "limit": "1",
        })
        return rows[0]["profile_id"] if rows else None

    async def review(
        self, admin_user_id: UUID, request_id: UUID, status: str, reason: str | None, university_id: UUID | None,
        document_hmac: bytes | None, student_hmac: bytes | None, key_version: int, ip: str | None,
    ) -> dict:
        """승인 · 반려와 작업 기록을 DB 함수 하나(한 트랜잭션)로. 충돌 이유는 CONFLICTS 의 글자 그대로 detail 이 된다."""
        return await self._rpc("admin_review_graduate_request", {
            "p_admin": str(admin_user_id), "p_request": str(request_id), "p_status": status, "p_reason": reason,
            "p_university": None if university_id is None else str(university_id),
            "p_document_hmac": None if document_hmac is None else bytea_literal(document_hmac),
            "p_student_hmac": None if student_hmac is None else bytea_literal(student_hmac),
            "p_key_version": key_version, "p_ip": ip,
        }, already=ALREADY_REVIEWED, conflicts=CONFLICTS)

