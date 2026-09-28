from datetime import datetime
from uuid import UUID

from fastapi import HTTPException

from app.core import errors
from app.core.http import error_code, raise_for_status
from app.core.postgrest import PostgrestRepository


class HeartTaskRepository(PostgrestRepository):
    """무료 하트 인증. 달 경계 · 한도 · 검수 중 판정은 DB 함수 한 곳에 있다(마이그레이션 20260928030100)."""

    async def fetch_status(self, profile_id: UUID) -> dict[str, dict]:
        """항목 이름 → {used, task_limit, reviewing, last_status, last_reject_reason}. 늘 세 항목이다."""
        response = await self._post("rpc/heart_task_status", json={"p_profile": str(profile_id)})
        raise_for_status(response)
        return {row["task"]: row for row in response.json()}

    async def submit(self, submission_id: UUID, profile_id: UUID, task: str, path: str, reward: int) -> None:
        response = await self._post("rpc/submit_heart_task", json={
            "p_id": str(submission_id), "p_profile": str(profile_id), "p_task": task,
            "p_path": path, "p_reward": reward,
        })
        # CM409 = 함수가 본 검수 중, 23505 = 거의 동시에 들어온 두 번째 제출(부분 unique 인덱스) — 둘 다 "이미 확인 중".
        if error_code(response) in ("CM409", "23505"):
            raise HTTPException(status_code=409, detail=errors.HEART_TASK_IN_REVIEW)
        if error_code(response) == "CM429":
            raise HTTPException(status_code=429, detail=errors.HEART_TASK_MONTHLY_LIMIT)
        raise_for_status(response)

    async def fetch_expired_proofs(self, reviewed_before: datetime, limit: int) -> list[dict]:
        """검수가 reviewed_before 보다 전에 끝났고 파일이 아직 남은 줄(D6 60일 정리)."""
        response = await self._get("heart_task_submissions", params={
            "select": "id,storage_path",
            "reviewed_at": f"lt.{reviewed_before.isoformat()}",
            "storage_path": "not.is.null",
            "order": "reviewed_at",
            "limit": str(limit),
        })
        raise_for_status(response)
        return response.json()

    async def clear_proof_paths(self, submission_ids: list[str]) -> None:
        """파일을 지운 줄의 경로를 비운다. 검수 끝난 줄에서 허락된 유일한 변경이다(C2 guard)."""
        response = await self._patch(
            "heart_task_submissions",
            params={"id": f"in.({','.join(submission_ids)})"},
            json={"storage_path": None},
        )
        raise_for_status(response)
