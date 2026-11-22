"""문의(inquiries) 저장소. 표는 RLS 정책 0개 · service_role 전용이다(20261110200000)."""
from datetime import datetime
from uuid import UUID

from app.core.http import error_code, raise_for_status
from app.core.postgrest import PostgrestRepository

# 관리자 목록(app/admin/inquiry_review.py) · 처리 응답 한 줄. 쓴 사람은 임베드로 한 번에 읽는다(탈퇴했으면 profile 이 null).
SELECT = ("id,reason,body,reply_email,status,admin_memo,created_at,updated_at,answered_at,"
           "profile:profiles(id,nickname,universities(name))")
_FK_VIOLATION = "23503"


class InquiryRepository(PostgrestRepository):

    async def count_since(self, profile_id: UUID | str, since: datetime, cap: int) -> int:
        """since 이후 내가 보낸 문의 수. 상한(cap)까지만 센다 — 넘었는지만 알면 된다."""
        response = await self._get("inquiries", params={
            "profile_id": f"eq.{profile_id}", "created_at": f"gte.{since.isoformat()}", "select": "id", "limit": str(cap),
        })
        raise_for_status(response)
        return len(response.json())

    async def insert(self, profile_id: UUID | str, reason: str, body: str, reply_email: str) -> str:
        """새 문의의 id. profiles 에 행이 아직 없는 사람(FK 23503)은 profile_id 를 비워 한 번 더 저장한다 — 문의는 막지 않는다."""
        row = {"profile_id": str(profile_id), "reason": reason, "body": body, "reply_email": reply_email}
        response = await self._post("inquiries", json=row, prefer="return=representation")
        if error_code(response) == _FK_VIOLATION:
            response = await self._post("inquiries", json={**row, "profile_id": None}, prefer="return=representation")
        raise_for_status(response)
        return response.json()[0]["id"]

    async def fetch_author(self, profile_id: UUID | str) -> tuple[str | None, str | None]:
        """알림 메일에 쓸 (닉네임, 학교 이름). profiles 행이 없거나 아직 비어 있으면 None."""
        response = await self._get("profiles", params={"id": f"eq.{profile_id}", "select": "nickname,universities(name)"})
        raise_for_status(response)
        rows = response.json()
        if not rows:
            return None, None
        return rows[0]["nickname"], (rows[0]["universities"] or {}).get("name")

    async def fetch(self, inquiry_id: UUID) -> dict | None:
        response = await self._get("inquiries", params={"select": SELECT, "id": f"eq.{inquiry_id}"})
        raise_for_status(response)
        rows = response.json()
        return rows[0] if rows else None

    async def update(self, inquiry_id: UUID, changes: dict) -> dict | None:
        """바꾼 뒤의 한 줄. 그사이 지워졌으면 None."""
        response = await self._patch("inquiries", params={"id": f"eq.{inquiry_id}", "select": SELECT},
                                     json=changes, prefer="return=representation")
        raise_for_status(response)
        rows = response.json()
        return rows[0] if rows else None
