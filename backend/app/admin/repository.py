"""관리자 명단(admin_users)과 작업 기록(admin_actions). 둘 다 RLS 정책 0개 · service_role 전용 표다(설계 10-18 §7)."""
from uuid import UUID

from app.core.http import raise_for_status
from app.core.postgrest import PostgrestRepository


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
