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

    async def fetch_pending(self, profile_id: UUID) -> list[dict]:
        """검수 중인 줄(오래된 순). 달과 상관없이 본다 — 지난달 말에 낸 것이 아직 검수 중이면 18a 에 보여야 한다."""
        response = await self._get("heart_task_submissions", params={
            "select": "id,task,created_at,storage_paths",
            "profile_id": f"eq.{profile_id}",
            "status": "eq.submitted",
            "order": "created_at.asc",
        })
        raise_for_status(response)
        return response.json()

    async def submit(self, submission_id: UUID, profile_id: UUID, task: str, paths: list[str], reward: int) -> None:
        response = await self._post("rpc/submit_heart_task", json={
            "p_id": str(submission_id), "p_profile": str(profile_id), "p_task": task,
            "p_paths": paths, "p_reward": reward,
        })
        # CM409 = 한도에 찼고 검수 중이 있음("결과를 기다려 달라"), CM429 = 한도에 찼고 검수 중 없음(이번 달 끝).
        # 같은 사람 · 항목의 동시 제출은 DB 함수의 락이 한 줄로 세워 두 번째가 위 둘 중 하나로 끝난다.
        if error_code(response) == "CM409":
            raise HTTPException(status_code=409, detail=errors.HEART_TASK_IN_REVIEW)
        if error_code(response) == "CM429":
            raise HTTPException(status_code=429, detail=errors.HEART_TASK_MONTHLY_LIMIT)
        raise_for_status(response)

    async def fetch_expired_proofs(self, reviewed_before: datetime, limit: int) -> list[dict]:
        """검수가 reviewed_before 보다 전에 끝났고 파일이 아직 남은 줄(D6 60일 정리). 줄마다 사진 1~3장이다.
        비운 줄(`{}`)을 걸러야 이미 정리한 줄이 매일 다시 뽑혀 100개 한도를 채우지 않는다."""
        response = await self._get("heart_task_submissions", params={
            "select": "id,storage_paths",
            "reviewed_at": f"lt.{reviewed_before.isoformat()}",
            "storage_paths": "not.eq.{}",
            "order": "reviewed_at",
            "limit": str(limit),
        })
        raise_for_status(response)
        return response.json()

    async def clear_proof_paths(self, submission_ids: list[str]) -> None:
        """파일을 지운 줄의 경로를 모두 비운다. 검수 끝난 줄에서 허락된 유일한 변경이다(guard)."""
        response = await self._patch(
            "heart_task_submissions",
            params={"id": f"in.({','.join(submission_ids)})"},
            json={"storage_paths": []},
        )
        raise_for_status(response)
