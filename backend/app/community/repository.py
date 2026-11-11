from datetime import datetime
from typing import Literal
from uuid import UUID

from fastapi import HTTPException

from app.core import errors
from app.core.http import error_code, raise_for_status
from app.core.postgrest import PostgrestRepository

# 한 번에 내려주는 질문 수. 앱 pollPageSize 와 같은 값이다.
POLL_PAGE_SIZE = 20
# 한 번에 내려주는 댓글 수(사용자 결정 「10개씩 불러오기」). 앱 commentPageSize 와 같은 값이다.
COMMENT_PAGE_SIZE = 10

# 15d 탭 줄. 전체 · 인기(최근 7일 참여 수 순, 한 쪽) · 내 질문 · 내 투표. DB poll_feed 의 p_tab 과 같은 값이다.
PollTab = Literal["all", "popular", "mine", "voted"]


class CommunityRepository(PostgrestRepository):
    """커뮤니티 질문 · 투표. 읽기와 쓰기가 DB 함수(RPC)를 거친다 — 집계 · 작성자 숨기기 · 하루 한도 ·
    투표 보상이 DB 한 곳에 있다(마이그레이션 20260927020100). 삭제만 PostgREST 로 바로 한다."""

    async def fetch_polls(self, viewer: UUID, *, poll_id: UUID | None = None,
                          before: datetime | None = None, before_id: UUID | None = None,
                          limit: int = POLL_PAGE_SIZE, tab: PollTab = "all") -> list[dict]:
        response = await self._post("rpc/poll_feed", json={
            "p_viewer": str(viewer),
            "p_poll_id": str(poll_id) if poll_id else None,
            "p_before": before.isoformat() if before else None,
            "p_before_id": str(before_id) if before_id else None,
            "p_limit": limit,
            "p_tab": tab,
        })
        raise_for_status(response)
        return response.json()

    async def create_poll(self, author: UUID, question: str, option_a: str, option_b: str) -> str:
        response = await self._post("rpc/create_poll", json={
            "p_author": str(author), "p_question": question, "p_option_a": option_a, "p_option_b": option_b,
        })
        if error_code(response) == "CM429":
            raise HTTPException(status_code=429, detail=errors.POLL_DAILY_LIMIT)
        raise_for_status(response)
        return response.json()

    async def cast_vote(self, poll_id: UUID, voter: UUID, choice: str) -> bool:
        """투표 + 하루 첫 투표 보상을 DB 한 트랜잭션에서. 돌려주는 값 = 하트를 줬는가."""
        response = await self._post("rpc/cast_poll_vote", json={
            "p_poll_id": str(poll_id), "p_voter": str(voter), "p_choice": choice,
        })
        # CM404 = 투표 전 확인에서 없음. 23503 = 확인과 insert 사이에 글이 지워져 FK 가 깨짐 — 둘 다 "없는 글" 이다.
        # 23503 을 그냥 두면 raise_for_status 가 422 "입력한 값을 다시 확인해 주세요" 를 낸다.
        if error_code(response) in ("CM404", "23503"):
            raise HTTPException(status_code=404, detail=errors.POLL_NOT_FOUND)
        raise_for_status(response, conflict_detail=errors.POLL_ALREADY_VOTED)
        return response.json()

    async def fetch_for_report(self, poll_id: UUID | str) -> dict | None:
        """신고(safety POST /reports)용 — 글쓴이와 가려진 글 · 글쓴이 상태까지 읽고 판단은 부르는 쪽이 한다.

        FK 힌트가 필요하다 — poll_votes(PK 가 두 FK)를 거치는 polls ↔ profiles 다대다가 하나 더 있어서 힌트가 없으면
        PostgREST 가 300(PGRST201)을 돌려준다."""
        response = await self._get("polls", {
            "id": f"eq.{poll_id}",
            "select": "id,author_id,question,option_a_label,option_b_label,status,created_at,"
                      "author:profiles!polls_author_id_fkey(status)",
        })
        raise_for_status(response)
        rows = response.json()
        return rows[0] if rows else None

    async def delete_poll(self, poll_id: UUID, author: UUID) -> bool:
        """본인 글이면 지우고 참. 투표는 cascade 로 같이 지워진다(사용자 결정 2)."""
        # 지워진 행을 돌려받아야 "없었다" 와 "지웠다" 를 가른다 — 부모 _delete 는 Prefer 를 받지 않는다.
        response = await self._client.delete(
            f"{self._postgrest_url}/polls",
            params={"id": f"eq.{poll_id}", "author_id": f"eq.{author}", "select": "id"},
            headers=self._with_prefer("return=representation"),
        )
        raise_for_status(response)
        return bool(response.json())

    async def fetch_comments(self, viewer: UUID, poll_id: UUID, *, after: datetime | None = None,
                             after_id: UUID | None = None, limit: int) -> list[dict]:
        """댓글 한 쪽(오래된 순). 글이 없거나 가려졌으면 404. 부르는 쪽이 has_more 를 알려고 limit 을 한 줄 더 준다."""
        response = await self._post("rpc/poll_comments_page", json={
            "p_viewer": str(viewer), "p_poll_id": str(poll_id),
            "p_after": after.isoformat() if after else None,
            "p_after_id": str(after_id) if after_id else None,
            "p_limit": limit,
        })
        if error_code(response) == "CM404":
            raise HTTPException(status_code=404, detail=errors.POLL_NOT_FOUND)
        raise_for_status(response)
        return response.json()

    async def add_comment(self, author: UUID, poll_id: UUID, body: str) -> dict:
        """댓글 쓰기 + 익명 번호 부여 + 하루 50개 한도 · 1분 5개 · 같은 내용 연달아 막기를 DB 한 트랜잭션에서. 새 댓글 한 줄(+ 푸시용 글쓴이 id · 질문)을 돌려준다."""
        response = await self._post("rpc/add_poll_comment", json={
            "p_author": str(author), "p_poll_id": str(poll_id), "p_body": body,
        })
        match error_code(response):
            case "CM429":
                raise HTTPException(status_code=429, detail=errors.POLL_COMMENT_DAILY_LIMIT)
            # 최근 1분 안 5개(마이그레이션 20261112090000). 하루 한도와 같은 429 지만 문구가 다르다.
            case "CM42B":
                raise HTTPException(status_code=429, detail=errors.POLL_COMMENT_TOO_FAST)
            # 같은 글에서 내 바로 전 댓글과 같은 본문. 앱은 409 + 문자열 detail 을 서버 문구 그대로 보인다.
            case "CM409":
                raise HTTPException(status_code=409, detail=errors.POLL_COMMENT_SAME_AS_LAST)
        # CM404 = 쓰기 전 확인에서 없음. 23503 = 확인과 insert 사이에 글이 지워져 FK 가 깨짐 — 둘 다 "없는 글" 이다.
        if error_code(response) in ("CM404", "23503"):
            raise HTTPException(status_code=404, detail=errors.POLL_NOT_FOUND)
        raise_for_status(response)
        return response.json()[0]

    async def delete_comment(self, viewer: UUID, comment_id: UUID) -> bool:
        """내 댓글이거나 내 글에 달린 댓글이면 지우고 참. 아니면(남의 것 · 없는 것) 거짓 — 부르는 쪽이 똑같이 404 로 답한다."""
        response = await self._post("rpc/delete_poll_comment", json={
            "p_viewer": str(viewer), "p_comment_id": str(comment_id),
        })
        raise_for_status(response)
        return bool(response.json())

    async def fetch_comment_for_report(self, comment_id: UUID | str) -> dict | None:
        """신고(safety POST /reports)용 — 댓글과 작성자 · 글 · 글쓴이 상태까지 읽고 판단은 부르는 쪽이 한다.

        FK 힌트가 필요하다 — 댓글 ↔ 프로필 · 글 ↔ 프로필은 다대다(poll_comment_aliases · poll_votes)가 하나씩 더 있어서
        힌트가 없으면 PostgREST 가 300(PGRST201)을 돌려준다."""
        response = await self._get("poll_comments", {
            "id": f"eq.{comment_id}",
            "select": "id,poll_id,author_id,body,status,created_at,"
                      "author:profiles!poll_comments_author_id_fkey(status),"
                      "poll:polls!poll_comments_poll_id_fkey(status,author:profiles!polls_author_id_fkey(status))",
        })
        raise_for_status(response)
        rows = response.json()
        return rows[0] if rows else None

    async def has_notification_since(self, profile_id: UUID | str, poll_id: UUID | str, since: datetime) -> bool:
        """이 글의 새 댓글 알림이 since 이후 이 사람 알림함에 이미 있는가 — 푸시 10분 묶음(comment_push)이 본다."""
        response = await self._get("notifications", {
            "profile_id": f"eq.{profile_id}", "kind": "eq.poll_comment", "data->>poll_id": f"eq.{poll_id}",
            "created_at": f"gte.{since.isoformat()}", "select": "id", "limit": "1",
        })
        raise_for_status(response)
        return bool(response.json())
