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
