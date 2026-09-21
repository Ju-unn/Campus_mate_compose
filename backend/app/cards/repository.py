from datetime import datetime, timedelta, timezone
from uuid import UUID

import httpx

from app.core.http import raise_for_status

# 카드 앞면(요약)과 뒷면(10b 상세)이 쓰는 프로필 컬럼. 실명·연락처는 한 글자도 넣지 않는다.
_CARD_PROFILE_COLUMNS = (
    "id,nickname,birth_year,major,animal_type,impression_type,"
    "interest_tags,my_traits,ideal_traits,ideal_note,bio,"
    "universities(name),profile_avatars(storage_path,status,created_at)"
)
# 10b 상세(`TORAs`)는 앞면 + 키·MBTI·학번·종교·흡연까지 본다. 실사진·연락처는 여전히 없다.
_CARD_DETAIL_COLUMNS = f"{_CARD_PROFILE_COLUMNS},height_cm,mbti,student_number,religion,is_smoker"
# 성향은 9축이고 축 번호 순서로 내려보낸다(조각 3 survey_vector 와 같은 번호).
SURVEY_AXES = range(1, 10)
_NOTIFICATION_COLUMNS = (
    "profile_id,card_arrived,acceptance_received,match_made,new_message,"
    "trust_reminder,new_friend_review,marketing,quiet_hours"
)
# 행이 없는 사람은 전부 켜진 것으로 본다(마케팅만 꺼짐) — C4 기본값과 같은 값이다.
NOTIFICATION_DEFAULTS = {
    "card_arrived": True, "acceptance_received": True, "match_made": True,
    "new_message": True, "trust_reminder": True, "new_friend_review": True,
    "marketing": False, "quiet_hours": True,
}


class CardRepository:
    """카드·매칭·알림 테이블 접근을 한 곳에 모은다(MatchingRepository 와 같은 패턴).
    프로필·후보 조회는 조각 3 MatchingRepository 를 그대로 쓴다 — 여기서 다시 만들지 않는다."""

    def __init__(self, postgrest_url: str, service_role_key: str, client: httpx.AsyncClient):
        self._postgrest_url = postgrest_url
        self._headers = {
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": "application/json",
        }
        self._client = client

    async def _get(self, path: str, params: dict) -> list[dict]:
        response = await self._client.get(
            f"{self._postgrest_url}/{path}", params=params, headers=self._headers
        )
        raise_for_status(response)
        return response.json()

    async def _post(self, path: str, json: dict | list, prefer: str = "return=representation",
                    params: dict | None = None) -> list[dict]:
        response = await self._client.post(
            f"{self._postgrest_url}/{path}", params=params, json=json,
            headers={**self._headers, "Prefer": prefer}
        )
        raise_for_status(response)
        return response.json() if response.content else []

    # 배치 ------------------------------------------------------------------
    async def fetch_region_settings(self) -> list[dict]:
        return await self._get("region_group_settings", {"select": "*"})

    async def fetch_active_counts(self) -> dict[str, dict[str, int]]:
        rows = await self._post("rpc/region_active_counts", {}, prefer="")
        counts: dict[str, dict[str, int]] = {}
        for row in rows:
            counts.setdefault(row["region_group"], {})[row["gender"]] = row["active_count"]
        return counts

    async def fetch_issue_owners(self) -> list[dict]:
        return await self._post("rpc/card_issue_owners", {}, prefer="")

    async def save_issue_weekdays(self, region_group: str, weekdays: list[int]) -> None:
        response = await self._client.patch(
            f"{self._postgrest_url}/region_group_settings",
            params={"region_group": f"eq.{region_group}"},
            json={"issue_weekdays": weekdays, "updated_at": "now()"},
            headers=self._headers,
        )
        raise_for_status(response)

    # 카드 ------------------------------------------------------------------
    async def insert_card(
        self, owner_id: UUID | str, target_id: UUID | str,
        expires_at: datetime | None, source: str = "daily",
    ) -> dict:
        rows = await self._post("daily_cards", {
            "owner_id": str(owner_id), "target_id": str(target_id),
            "source": source, "expires_at": expires_at.isoformat() if expires_at else None,
        })
        return rows[0]

    async def fetch_live_cards(self, owner_id: UUID | str) -> list[dict]:
        """아직 결정하지 않았고 만료도 되지 않은 카드. 노출 순서는 설계 §2.4 대로
        [이번 주기 무료 → 이전 주기 구매] 라서 issued_at 오름차순이 아니라 source 로 정렬한다."""
        rows = await self._get("daily_cards", {
            "owner_id": f"eq.{owner_id}",
            "select": "id,target_id,source,issued_at,expires_at,card_decisions(card_id)",
            "or": "(expires_at.is.null,expires_at.gt.now())",
            "order": "issued_at.desc",
        })
        # card_decisions.card_id 가 PK 라 임베드는 배열이 아니라 객체/null 이다 — 결정이 없으면 null.
        return [row for row in rows if not row["card_decisions"]]

    async def fetch_card(self, card_id: UUID | str) -> dict | None:
        """card_decisions·acceptance_responses 는 card_id 가 PK 이자 daily_cards 참조라
        PostgREST 가 one-to-one 으로 보고 객체 하나(없으면 null)를 준다 — 목록이 아니다."""
        rows = await self._get("daily_cards", {
            "id": f"eq.{card_id}",
            "select": "id,owner_id,target_id,source,issued_at,expires_at,"
                      "card_decisions(decision,decided_at),acceptance_responses(responder_id)",
        })
        return rows[0] if rows else None

    async def insert_decision(self, card_id: UUID | str, decision: str) -> None:
        await self._post("card_decisions", {"card_id": str(card_id), "decision": decision}, prefer="")

    # 받은 수락함 -------------------------------------------------------------
    async def fetch_pending_acceptances(self, profile_id: UUID | str, days: int = 7) -> list[dict]:
        """내가 받은 수락 중 7일이 지나지 않았고 아직 답하지 않은 것(설계 §2.2, 2026-09-21 확정).
        건수가 1인당 하루 0.3~0.5건이라 응답 여부는 파이썬에서 거른다 — 전용 SQL 함수를 만들지 않는다.
        card_decisions 와 acceptance_responses 사이에는 FK 가 없어(둘 다 daily_cards 만 가리킨다)
        곧바로 임베드하면 PGRST200 이다 — daily_cards 를 거쳐서 붙인다."""
        since = datetime.now(timezone.utc) - timedelta(days=days)
        rows = await self._get("card_decisions", {
            "select": "card_id,decided_at,"
                      "daily_cards!inner(id,owner_id,target_id,acceptance_responses(card_id))",
            "decision": "eq.accept",
            "decided_at": f"gte.{since.isoformat()}", "daily_cards.target_id": f"eq.{profile_id}",
            "order": "decided_at.desc",
        })
        return [row for row in rows if not row["daily_cards"]["acceptance_responses"]]

    async def insert_acceptance_response(
        self, card_id: UUID | str, responder_id: UUID | str, decision: str
    ) -> None:
        await self._post("acceptance_responses", {
            "card_id": str(card_id), "responder_id": str(responder_id), "decision": decision,
        }, prefer="")

    async def create_match(self, profile_a: UUID | str, profile_b: UUID | str) -> dict:
        """C3 의 check (profile_a < profile_b) 를 지키려고 여기서 한 번만 정렬한다.
        A→B, B→A 카드가 같은 날 나가면 두 사람이 각각 매칭을 만들려 해서 두 번 들어온다.
        나중 쪽이 matches_pair_unique 로 터지지 않게 upsert 로 기존 행을 그대로 돌려준다."""
        first, second = sorted([str(profile_a), str(profile_b)])
        rows = await self._post(
            "matches", {"profile_a": first, "profile_b": second},
            prefer="resolution=merge-duplicates,return=representation",
            params={"on_conflict": "profile_a,profile_b"},
        )
        match = rows[0]
        await self._post("match_participants", [
            {"match_id": match["id"], "profile_id": first},
            {"match_id": match["id"], "profile_id": second},
        ], prefer="resolution=merge-duplicates", params={"on_conflict": "match_id,profile_id"})
        return match

    # 프로필 요약 --------------------------------------------------------------
    async def fetch_card_profile(self, profile_id: UUID | str) -> dict:
        rows = await self._get("profiles", {"id": f"eq.{profile_id}", "select": _CARD_PROFILE_COLUMNS})
        return rows[0] if rows else {}

    async def fetch_card_detail_profile(self, profile_id: UUID | str) -> dict:
        rows = await self._get("profiles", {"id": f"eq.{profile_id}", "select": _CARD_DETAIL_COLUMNS})
        return rows[0] if rows else {}

    async def fetch_survey(self, profile_id: UUID | str) -> list[float]:
        """9축을 번호 순서로. 답하지 않은 축은 0 이다 — 화면이 빈 칸 대신 가운데를 그린다."""
        rows = await self._get("survey_answers", {
            "profile_id": f"eq.{profile_id}", "select": "axis,value",
        })
        answers = {int(row["axis"]): float(row["value"]) for row in rows}
        return [answers.get(axis, 0.0) for axis in SURVEY_AXES]

    async def fetch_region_group(self, profile_id: UUID | str) -> str | None:
        """지역그룹은 프로필이 아니라 학교가 들고 있다(universities.region_group)."""
        rows = await self._get("profiles", {
            "id": f"eq.{profile_id}", "select": "universities(region_group)",
        })
        if not rows:
            return None
        return (rows[0].get("universities") or {}).get("region_group")

    # 푸시 · 알림 --------------------------------------------------------------
    async def upsert_push_token(self, token: str, profile_id: UUID | str, platform: str) -> None:
        await self._post("push_tokens", {
            "token": token, "profile_id": str(profile_id), "platform": platform, "updated_at": "now()",
        }, prefer="resolution=merge-duplicates")

    async def delete_push_token(self, token: str) -> None:
        response = await self._client.delete(
            f"{self._postgrest_url}/push_tokens",
            params={"token": f"eq.{token}"}, headers=self._headers,
        )
        raise_for_status(response)

    async def fetch_push_tokens(self, profile_id: UUID | str) -> list[str]:
        rows = await self._get("push_tokens", {"profile_id": f"eq.{profile_id}", "select": "token"})
        return [row["token"] for row in rows]

    async def fetch_notification_settings(self, profile_id: UUID | str) -> dict:
        rows = await self._get("notification_settings", {
            "profile_id": f"eq.{profile_id}", "select": _NOTIFICATION_COLUMNS,
        })
        return rows[0] if rows else {"profile_id": str(profile_id), **NOTIFICATION_DEFAULTS}

    async def update_notification_settings(self, profile_id: UUID | str, **fields) -> None:
        await self._post("notification_settings", {
            "profile_id": str(profile_id), **fields,
        }, prefer="resolution=merge-duplicates")

    async def set_matching_paused(self, profile_id: UUID | str, paused: bool) -> None:
        response = await self._client.patch(
            f"{self._postgrest_url}/profiles",
            params={"id": f"eq.{profile_id}"},
            json={"matching_paused": paused},
            headers=self._headers,
        )
        raise_for_status(response)
