import logging
from datetime import datetime
from uuid import UUID

from app.core.http import raise_for_status
from app.core.postgrest import PostgrestRepository

logger = logging.getLogger(__name__)

# 방을 열 때 한 번에 가져오는 메시지 수(결정 9). 위로 올리면 같은 수만큼 더 가져온다.
MESSAGE_PAGE_SIZE = 50
# 메시지 길이 상한(결정 8). DB 체크 제약(messages_body_length)과 같은 값이다.
MESSAGE_MAX_LENGTH = 1000
# 안 읽은 수는 뱃지에만 쓴다. 이보다 많으면 화면이 "99+" 로 보여 주므로 더 셀 이유가 없다.
UNREAD_COUNT_CAP = 100
# PostgREST db-max-rows 에 조용히 잘리지 않게 상한을 우리가 정한다(조각 4 리뷰 권고 2번과 같은 이유).
_CONVERSATION_LIMIT = 200
_OPEN_MATCH_LIMIT = 5000

_MATCH_COLUMNS = "id,profile_a,profile_b,created_at,trust_passed_at,chat_closed_at"
_PARTICIPANT_COLUMNS = "profile_id,trust_response,left_at,last_read_at"
_MESSAGE_COLUMNS = "id,sender_id,kind,body,created_at"


class ChatRepository(PostgrestRepository):
    """채팅이 건드리는 세 테이블(messages · match_participants · matches)의 유일한 출입구."""

    async def _rows(self, path: str, params: dict) -> list[dict]:
        response = await self._get(path, params=params)
        raise_for_status(response)
        return response.json()

    async def _rows_post(self, path: str, json: dict | list) -> list[dict]:
        response = await self._post(path, json=json, prefer="return=representation")
        raise_for_status(response)
        return response.json() if response.content else []

    async def _rows_patch(self, path: str, params: dict, json: dict) -> list[dict]:
        """고친 행을 돌려받는다. 조건을 같이 걸면 "이번에 내가 고쳤나" 를 행 수로 알 수 있다."""
        response = await self._patch(path, params=params, json=json, prefer="return=representation")
        raise_for_status(response)
        return response.json() if response.content else []

    # 대화 목록 · 방 --------------------------------------------------------
    async def fetch_conversations(self, profile_id: UUID | str) -> list[dict]:
        """대화 목록(화면 13 "대화 중")의 내 참가자 행 + 매칭.

        빼는 것은 둘뿐이다 — 닫힌 방(결정 3: 지우지 않고 숨기기만 한다)과 내가 나간 방(결정 7).
        **상대가 나간 방은 그대로 남는다.** 그래서 상대 쪽 left_at 은 조건에 넣지 않는다."""
        return await self._rows("match_participants", {
            "profile_id": f"eq.{profile_id}",
            "left_at": "is.null",
            "select": f"match_id,last_read_at,trust_response,matches!inner({_MATCH_COLUMNS})",
            "matches.chat_closed_at": "is.null",
            "limit": _CONVERSATION_LIMIT,
        })

    async def fetch_match(self, match_id: UUID | str, profile_id: UUID | str) -> dict | None:
        """방 하나 + 참가자 두 행. 당사자가 아니면 None — 라우터가 404 로 바꾼다."""
        rows = await self._rows("matches", {
            "id": f"eq.{match_id}",
            "select": f"{_MATCH_COLUMNS},match_participants({_PARTICIPANT_COLUMNS})",
        })
        if not rows:
            return None
        match = rows[0]
        if not any(p["profile_id"] == str(profile_id) for p in match["match_participants"]):
            return None
        return match

    async def fetch_partner_profile(self, profile_id: UUID | str) -> dict:
        """상대의 닉네임·아바타. 실명·연락처는 한 글자도 가져오지 않는다(설계 §7.1)."""
        rows = await self._rows("profiles", {
            "id": f"eq.{profile_id}",
            "select": "id,nickname,profile_avatars(storage_path,status,created_at)",
        })
        return rows[0] if rows else {}

    async def fetch_nickname(self, profile_id: UUID | str) -> str:
        """시스템 줄 문장에 들어갈 이름. 채팅에서 보이는 이름은 늘 닉네임이다(DESIGN §8.7)."""
        rows = await self._rows("profiles", {"id": f"eq.{profile_id}", "select": "nickname"})
        return rows[0]["nickname"] if rows else ""

    # 메시지 ----------------------------------------------------------------
    async def fetch_messages(self, match_id: UUID | str, before: datetime | None = None,
                             before_id: UUID | str | None = None,
                             limit: int = MESSAGE_PAGE_SIZE) -> list[dict]:
        """최근 것부터 limit 건. 커서(`before`·`before_id`)가 있으면 그보다 오래된 것만 준다.

        **커서가 시각 하나가 아니라 (시각, id) 쌍인 이유**: 같은 트랜잭션에서 들어간 두 줄은
        created_at 이 정확히 같을 수 있다. 시각만으로 `lt` 를 걸면 그 둘 중 하나가 페이지 경계에서
        영영 건너뛰어진다. id 를 두 번째 열쇠로 써서 순서를 완전히 정한다."""
        params = {
            "match_id": f"eq.{match_id}",
            "select": _MESSAGE_COLUMNS,
            "order": "created_at.desc,id.desc",
            "limit": limit,
        }
        if before is not None:
            cursor = before.isoformat()
            if before_id:
                params["or"] = (
                    f"(created_at.lt.{cursor},and(created_at.eq.{cursor},id.lt.{before_id}))"
                )
            else:
                # id 가 없으면 고를 것이 하나뿐이라 or 로 감쌀 이유가 없다.
                params["created_at"] = f"lt.{cursor}"
        return await self._rows("messages", params)

    async def fetch_last_message(self, match_id: UUID | str) -> dict | None:
        """목록 한 줄의 미리보기. 시스템 줄도 똑같이 마지막 줄이 된다(결정 7·10)."""
        rows = await self.fetch_messages(match_id, limit=1)
        return rows[0] if rows else None

    async def insert_message(self, match_id: UUID | str, sender_id: UUID | str,
                             body: str, kind: str = "text") -> dict:
        """kind 는 'text'(사람이 쓴 말풍선) · 'left' · 'trust_accept'. 시스템 줄도 같은 문으로 들어간다 —
        그래서 목록의 마지막 줄 · 안 읽은 수 · Realtime 구독 · 푸시가 전부 그대로 따라온다."""
        rows = await self._rows_post("messages", {
            "match_id": str(match_id), "sender_id": str(sender_id), "kind": kind, "body": body,
        })
        return rows[0]

    async def count_unread(self, match_id: UUID | str, profile_id: UUID | str,
                           last_read_at: str | None) -> int:
        """안 읽은 수는 내 last_read_at 기준이고 내가 보낸 것은 세지 않는다(ERD §4).
        상대에게 보이는 읽음 표시는 없다 — 이 값은 내 화면의 뱃지에만 쓴다."""
        params = {
            "match_id": f"eq.{match_id}",
            "sender_id": f"neq.{profile_id}",
            "select": "id",
            "limit": UNREAD_COUNT_CAP,
        }
        if last_read_at:
            params["created_at"] = f"gt.{last_read_at}"
        return len(await self._rows("messages", params))

    async def touch_read(self, match_id: UUID | str, profile_id: UUID | str, now: datetime) -> None:
        """방에 들어올 때와 나갈 때 한 번씩 부른다(ERD §4). 메시지마다 갱신하지 않는다."""
        response = await self._patch("match_participants", params={
            "match_id": f"eq.{match_id}", "profile_id": f"eq.{profile_id}",
        }, json={"last_read_at": now.isoformat()})
        raise_for_status(response)

    # 나가기 · 게이트 --------------------------------------------------------
    async def leave(self, match_id: UUID | str, profile_id: UUID | str, now: datetime) -> bool:
        """left_at 을 찍는다. 이미 찍혀 있으면 False — 시스템 줄을 두 번 넣지 않는다.
        게이트 거절도 여기로 온다(결정 11) — 서버는 나가기와 거절을 구분하지 않는다."""
        rows = await self._rows_patch("match_participants", {
            "match_id": f"eq.{match_id}", "profile_id": f"eq.{profile_id}", "left_at": "is.null",
        }, {"left_at": now.isoformat()})
        return bool(rows)

    async def leave_and_announce(self, match_id: UUID | str, profile_id: UUID | str,
                                 now: datetime) -> bool:
        """나가기 한 번. `/leave` 와 차단(조각 6)이 같이 쓴다 — 상대에게 둘이 글자까지 같아야
        차단 사실이 새지 않는다(설계 §7.2). 이번에 나갔으면 True.

        left_at 을 먼저 찍고 시스템 줄을 나중에 넣는다. 반대로 하면 줄만 남고 나가기가 실패할 수 있다.
        푸시는 보내지 않는다 — 나갔다는 소식으로 알림을 울릴 일은 아니다. 다음에 방을 열면 보인다."""
        if not await self.leave(match_id, profile_id, now):
            return False
        nickname = await self.fetch_nickname(profile_id)
        await self.insert_message(match_id, profile_id, f"{nickname}님이 채팅방을 나갔어요", kind="left")
        return True

    async def save_trust_accept(self, match_id: UUID | str, profile_id: UUID | str,
                                now: datetime) -> bool:
        """아직 응답하지 않았을 때만 'accept' 를 쓴다. 이미 있으면 False.
        거절을 쓰는 메서드는 없다 — 거절은 leave() 다(결정 11)."""
        rows = await self._rows_patch("match_participants", {
            "match_id": f"eq.{match_id}", "profile_id": f"eq.{profile_id}",
            "trust_response": "is.null",
        }, {"trust_response": "accept", "responded_at": now.isoformat()})
        return bool(rows)

    async def pass_trust_gate(self, match_id: UUID | str, now: datetime) -> bool:
        """trust_passed_at 을 지금으로 찍는다. 이미 찍혀 있으면 False — 푸시를 두 번 보내지 않는다."""
        rows = await self._rows_patch("matches", {
            "id": f"eq.{match_id}", "trust_passed_at": "is.null",
        }, {"trust_passed_at": now.isoformat()})
        return bool(rows)

    async def close_chat(self, match_id: UUID | str, now: datetime) -> bool:
        """chat_closed_at 을 찍는다. 이미 찍혀 있으면 False.
        메시지는 지우지 않는다(결정 3·4) — 목록에서 빠질 뿐이다."""
        rows = await self._rows_patch("matches", {
            "id": f"eq.{match_id}", "chat_closed_at": "is.null",
        }, {"chat_closed_at": now.isoformat()})
        return bool(rows)

    async def fetch_open_matches(self, limit: int = _OPEN_MATCH_LIMIT) -> list[dict]:
        """아직 통과도 종료도 하지 않은 매칭 + 참가자 두 행(매시 배치용)."""
        rows = await self._rows("matches", {
            "trust_passed_at": "is.null",
            "chat_closed_at": "is.null",
            "select": f"{_MATCH_COLUMNS},match_participants({_PARTICIPANT_COLUMNS})",
            "limit": limit,
        })
        if len(rows) >= limit:
            # 잘린 줄 모르면 뒤쪽 매칭이 리마인드도 마감도 못 받고 조용히 밀린다.
            logger.warning("열린 매칭이 상한 %s 에 닿았다 — 배치를 나눌 때가 됐다", limit)
        return rows

    # 게이트를 통과한 뒤에만 부르는 것 ------------------------------------------
    async def fetch_kakao_id(self, profile_id: UUID | str) -> str | None:
        """앱에는 FastAPI 가 내려준다 — profile_private 는 authenticated 에게 열려 있지 않다(ERD §11-20)."""
        rows = await self._rows("profile_private", {
            "profile_id": f"eq.{profile_id}", "select": "kakao_id",
        })
        return rows[0]["kakao_id"] if rows else None

    async def fetch_photo_paths(self, profile_id: UUID | str) -> list[str]:
        """실사진 경로(대표 사진이 0번). 비공개 버킷이라 라우터가 서명 URL 로 바꿔 내려보낸다."""
        rows = await self._rows("profile_photos", {
            "profile_id": f"eq.{profile_id}", "select": "storage_path,position", "order": "position.asc",
        })
        return [row["storage_path"] for row in rows]
