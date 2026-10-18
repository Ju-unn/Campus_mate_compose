"""관리자 명단(admin_users)과 작업 기록(admin_actions). 둘 다 RLS 정책 0개 · service_role 전용 표다(설계 10-18 §7).
인증샷 검수(§8-1)도 여기서 읽고 DB 함수 admin_review_heart_task 로 바꾼다."""
from uuid import UUID

from fastapi import HTTPException

from app.core import errors
from app.core.http import error_code, raise_for_status
from app.core.postgrest import PostgrestRepository

# 관리자 웹이 읽는 기계용 이유 코드(caller.py 의 mfa_required · not_admin 과 같은 결).
NOT_FOUND = "not_found"
ALREADY_REVIEWED = "already_reviewed"
# 검수 화면 한 줄에 필요한 칸. storage_path 는 서명 URL 을 만드는 데만 쓰고 응답에는 싣지 않는다.
_SUBMISSION_SELECT = ("id,task,status,reject_reason,reward_hearts,created_at,reviewed_at,storage_path,"
                      "profiles(id,nickname,universities(name))")


class AdminRepository(PostgrestRepository):

    async def is_admin(self, user_id: UUID) -> bool:
        response = await self._get("admin_users", params={"user_id": f"eq.{user_id}", "select": "user_id"})
        # 명단을 못 읽으면 500 이다 — "관리자 아님" 으로도 "관리자" 로도 넘기지 않는다.
        response.raise_for_status()
        return bool(response.json())

    async def record_action(
        self, admin_user_id: UUID, action: str, *,
        target_type: str | None = None, target_id: str | None = None,
        before: dict | None = None, after: dict | None = None,
        reason: str | None = None, ip: str | None = None,
    ) -> None:
        """작업 기록 한 줄. 관리자 쓰기 경로는 모두 같은 요청 안에서 이걸 부르고, 실패는 삼키지 않는다 —
        기록 없는 조치를 남기지 않으려면 요청도 실패해야 한다(설계 §8 머리).
        before · after 에 전화번호 · 카카오톡 아이디 원문을 넣지 않는다(열람은 "열람했다" 만 남긴다).
        표의 check(동작 이름 형식 · 사유 길이) 위반은 422, 그 밖의 실패는 500 이다(core/http.raise_for_status)."""
        response = await self._post("admin_actions", json={
            "admin_user_id": str(admin_user_id), "action": action,
            "target_type": target_type, "target_id": target_id,
            "before": before, "after": after, "reason": reason, "ip": ip,
        })
        raise_for_status(response)

    async def list_heart_submissions(self, status: str, task: str | None, limit: int) -> list[dict]:
        """오래된 순(먼저 낸 사람부터 본다)."""
        params = {"select": _SUBMISSION_SELECT, "status": f"eq.{status}", "order": "created_at.asc", "limit": str(limit)}
        if task:
            params["task"] = f"eq.{task}"
        response = await self._get("heart_task_submissions", params=params)
        raise_for_status(response)
        return response.json()

    async def fetch_heart_submission(self, submission_id: UUID) -> dict | None:
        response = await self._get("heart_task_submissions", params={
            "select": _SUBMISSION_SELECT, "id": f"eq.{submission_id}",
        })
        raise_for_status(response)
        rows = response.json()
        return rows[0] if rows else None

    async def fetch_previous_heart_submissions(
        self, profile_id: str, task: str, exclude_id: str, limit: int = 5,
    ) -> list[dict]:
        """같은 사람 · 같은 항목의 다른 제출 중 사진이 남은 것, 최근 순 — "이미 쓴 캡처예요" 판단용."""
        response = await self._get("heart_task_submissions", params={
            "select": "id,status,created_at,storage_path",
            "profile_id": f"eq.{profile_id}", "task": f"eq.{task}", "id": f"neq.{exclude_id}",
            "storage_path": "not.is.null", "order": "created_at.desc", "limit": str(limit),
        })
        raise_for_status(response)
        return response.json()

    async def review_heart_task(
        self, admin_user_id: UUID, submission_id: UUID, status: str, reject_reason: str | None, ip: str | None,
    ) -> dict:
        """승인 · 반려와 작업 기록을 DB 함수 하나(한 트랜잭션)로. 하트 지급은 기존 트리거가 같은 트랜잭션에서 한다."""
        response = await self._post("rpc/admin_review_heart_task", json={
            "p_admin": str(admin_user_id), "p_submission": str(submission_id), "p_status": status,
            "p_reject_reason": reject_reason, "p_ip": ip,
        })
        match error_code(response):
            case "CM404":
                raise HTTPException(status_code=404, detail=NOT_FOUND)
            case "CM409":
                raise HTTPException(status_code=409, detail=ALREADY_REVIEWED)
            case "22023":
                raise HTTPException(status_code=422, detail=errors.INVALID_INPUT)
        raise_for_status(response)
        return response.json()
