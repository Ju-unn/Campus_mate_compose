"""관리자 명단(admin_users)과 작업 기록(admin_actions). 둘 다 RLS 정책 0개 · service_role 전용 표다(설계 10-18 §7).
인증샷 검수(§8-1)도 여기서 읽고 DB 함수 admin_review_heart_task 로 바꾼다. 신고 검수(§8-2)도 여기서 읽는다."""
import asyncio
from uuid import UUID

from fastapi import HTTPException

from app.core import errors
from app.core.http import error_code, raise_for_status
from app.core.postgrest import PostgrestRepository

# 관리자 웹이 읽는 기계용 이유 코드(caller.py 의 mfa_required · not_admin 과 같은 결).
NOT_FOUND = "not_found"
ALREADY_REVIEWED = "already_reviewed"
# 신고 닫기 · 정지 · 해제 · 가림 해제 · 글 가림에서 "이미 그 상태" (두 관리자가 같은 건을 누른 두 번째).
ALREADY_DONE = "already_done"
# 검수 화면 한 줄에 필요한 칸. storage_path 는 서명 URL 을 만드는 데만 쓰고 응답에는 싣지 않는다.
_SUBMISSION_SELECT = ("id,task,status,reject_reason,reward_hearts,created_at,reviewed_at,storage_path,"
                      "profiles(id,nickname,universities(name))")
# 신고 목록 한 줄. reports 는 profiles 를 두 번 가리켜서(reporter_id · target_profile_id) 신고당한 쪽을 FK 칸 이름으로 짚는다.
# 신고자는 싣지 않는다. 사본(target_snapshot)은 한 건을 고를 때만 읽는다.
_REPORT_SELECT = ("id,target_type,target_id,reason,reason_note,status,created_at,resolved_at,"
                  "target_profile:profiles!target_profile_id(id,nickname,status,auto_hidden_at,universities(name))")
# 신고 대상 종류(report_target) → 글 표. 둘 다 status 가 content_status(visible · blinded)다.
CONTENT_TABLES = {"poll": "polls", "friend_review": "friend_reviews"}
_MESSAGE_SELECT = "id,sender_id,kind,body,created_at"


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

    async def _rows(self, path: str, params: dict) -> list[dict]:
        response = await self._get(path, params=params)
        raise_for_status(response)
        return response.json()

    async def list_reports(self, status: str, target_type: str | None, limit: int) -> list[dict]:
        """오래된 순(애플 1.2 신속 조치 — 먼저 들어온 신고부터 본다)."""
        params = {"select": _REPORT_SELECT, "status": f"eq.{status}", "order": "created_at.asc", "limit": str(limit)}
        if target_type:
            params["target_type"] = f"eq.{target_type}"
        return await self._rows("reports", params)

    async def fetch_report(self, report_id: UUID) -> dict | None:
        rows = await self._rows("reports", {"select": f"{_REPORT_SELECT},target_snapshot", "id": f"eq.{report_id}"})
        return rows[0] if rows else None

    async def fetch_other_reports(self, target_profile_id: str, exclude_id: str, limit: int = 20) -> list[dict]:
        """같은 사람을 향한 다른 신고, 최근 순. 신고자 id 는 싣지 않는다."""
        return await self._rows("reports", {
            "select": "id,target_type,reason,status,created_at",
            "target_profile_id": f"eq.{target_profile_id}", "id": f"neq.{exclude_id}",
            "order": "created_at.desc", "limit": str(limit),
        })

    async def fetch_content_status(self, target_type: str, content_id: str) -> str | None:
        """투표 글 · 지인 리뷰의 지금 상태. 글이 아닌 신고이거나 글이 지워졌으면 None."""
        table = CONTENT_TABLES.get(target_type)
        if table is None:
            return None
        rows = await self._rows(table, {"id": f"eq.{content_id}", "select": "status"})
        return rows[0]["status"] if rows else None

    async def fetch_chat_context(self, match_id: str, message_id: str, created_at: str, each_side: int) -> list[dict]:
        """신고된 줄과 그 앞뒤 each_side 줄, 오래된 순. 세 조회 모두 messages_match_created_index(match_id, created_at) 를 탄다.
        shortcut: 신고된 줄과 created_at 이 똑같은 다른 줄은 앞뒤 어디에도 안 잡힌다 — 마이크로초까지 같을 일이 드물어 그대로 둔다."""
        room = {"match_id": f"eq.{match_id}", "select": _MESSAGE_SELECT}
        before, line, after = await asyncio.gather(
            self._rows("messages", {**room, "created_at": f"lt.{created_at}", "order": "created_at.desc", "limit": str(each_side)}),
            self._rows("messages", {**room, "id": f"eq.{message_id}"}),
            self._rows("messages", {**room, "created_at": f"gt.{created_at}", "order": "created_at.asc", "limit": str(each_side)}),
        )
        return [*reversed(before), *line, *after]

    async def review_heart_task(
        self, admin_user_id: UUID, submission_id: UUID, status: str, reject_reason: str | None, ip: str | None,
    ) -> dict:
        """승인 · 반려와 작업 기록을 DB 함수 하나(한 트랜잭션)로. 하트 지급은 기존 트리거가 같은 트랜잭션에서 한다."""
        return await self._rpc("admin_review_heart_task", {
            "p_admin": str(admin_user_id), "p_submission": str(submission_id), "p_status": status,
            "p_reject_reason": reject_reason, "p_ip": ip,
        }, already=ALREADY_REVIEWED)

    async def resolve_report(
        self, admin_user_id: UUID, report_id: UUID, outcome: str, note: str | None, same_target: bool, ip: str | None,
    ) -> dict:
        """조치 완료 / 기각과 작업 기록(닫힌 신고마다 한 줄)을 DB 함수 하나로. same_target 이면 같은 사람의 열린 신고도 닫는다."""
        return await self._rpc("admin_resolve_report", {
            "p_admin": str(admin_user_id), "p_report": str(report_id), "p_outcome": outcome, "p_note": note,
            "p_same_target": same_target, "p_ip": ip,
        })

    async def act_on_profile(self, action: str, admin_user_id: UUID, profile_id: UUID, reason: str, ip: str | None) -> dict:
        """action = suspend · unsuspend · unhide → DB 함수 admin_{action}_profile. 가림 해제는 그 사람의 열린 신고 기각까지 함께 한다."""
        return await self._rpc(f"admin_{action}_profile", {
            "p_admin": str(admin_user_id), "p_profile": str(profile_id), "p_reason": reason, "p_ip": ip,
        })

    async def set_content_status(
        self, admin_user_id: UUID, target_type: str, content_id: UUID, status: str, reason: str, ip: str | None,
    ) -> dict:
        """투표 글 · 지인 리뷰 가림 / 해제와 작업 기록. target_type 은 report_target 값(poll · friend_review)이다."""
        return await self._rpc("admin_set_content_status", {
            "p_admin": str(admin_user_id), "p_target": target_type, "p_content": str(content_id), "p_status": status,
            "p_reason": reason, "p_ip": ip,
        })

    async def _rpc(self, name: str, body: dict, already: str = ALREADY_DONE) -> dict:
        """조치 DB 함수들의 오류 약속(CM404 · CM409 · 22023)을 HTTP 로 바꾼다. 그 밖의 check 위반(기록 사유 500자 등)은 422."""
        response = await self._post(f"rpc/{name}", json=body)
        match error_code(response):
            case "CM404":
                raise HTTPException(status_code=404, detail=NOT_FOUND)
            case "CM409":
                raise HTTPException(status_code=409, detail=already)
            case "22023":
                raise HTTPException(status_code=422, detail=errors.INVALID_INPUT)
        raise_for_status(response)
        return response.json()
