import logging
from datetime import datetime, timedelta, timezone
from uuid import UUID

from fastapi import HTTPException

from app.core import errors
from app.core.http import error_code, raise_for_status
from app.core.postgrest import PostgrestRepository

logger = logging.getLogger(__name__)

# PostgREST 의 db-max-rows 에 조용히 잘리지 않게 우리가 상한을 정해 놓고, 거기 닿으면 경고를 남긴다.
# 잘린 줄 모르고 지나가면 이미 카드를 받은 사람이 목록에서 빠져 한 장을 더 받는다(리뷰 권고 2번).
_ISSUED_OWNERS_LIMIT = 5000

# 카드 앞면(요약)과 뒷면(10b 상세)이 쓰는 프로필 컬럼. 실명·연락처는 한 글자도 넣지 않는다.
# status · auto_hidden_at 은 응답에 싣지 않는다 — "카드에서 사라져야 하는가"(조각 6)를 가르는 재료다.
_CARD_PROFILE_COLUMNS = (
    "id,nickname,birth_year,major,animal_type,impression_type,"
    "interest_tags,my_traits,ideal_traits,ideal_note,bio,status,auto_hidden_at,"
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


_OFFER_COLUMNS = "id,owner_id,cycle_started_at,target_id,reasons,band_count,status,purchased_card_id"
# 유료 카드 제안 대상의 자격(조각 6 판정 + 일시중지)과 흐린 아바타 주소만 읽는다 — 다른 프로필 칸은 읽지도 않는다.
_OFFER_TARGET_COLUMNS = "id,status,auto_hidden_at,matching_paused,profile_avatars(storage_path,status,created_at)"


class PaidOfferConflict(Exception):
    """같은 사람 · 같은 주기에 offered 제안이 이미 있다(부분 유일 인덱스, 동시 요청). 부른 쪽이 다시 읽는다."""


class CardRepository(PostgrestRepository):
    """카드·매칭·알림 테이블 접근을 한 곳에 모은다(MatchingRepository 와 같은 패턴).
    프로필·후보 조회는 조각 3 MatchingRepository 를 그대로 쓴다 — 여기서 다시 만들지 않는다."""

    async def _rows(self, path: str, params: dict) -> list[dict]:
        response = await self._get(path, params=params)
        raise_for_status(response)
        return response.json()

    async def _rows_post(self, path: str, json: dict | list, prefer: str = "return=representation",
                         params: dict | None = None) -> list[dict]:
        response = await self._post(path, json=json, params=params, prefer=prefer)
        raise_for_status(response)
        return response.json() if response.content else []

    # 배치 ------------------------------------------------------------------
    async def fetch_region_settings(self) -> list[dict]:
        return await self._rows("region_group_settings", {"select": "*"})

    async def fetch_active_counts(self) -> dict[str, dict[str, int]]:
        rows = await self._rows_post("rpc/region_active_counts", {}, prefer="")
        counts: dict[str, dict[str, int]] = {}
        for row in rows:
            counts.setdefault(row["region_group"], {})[row["gender"]] = row["active_count"]
        return counts

    async def fetch_issue_owners(self) -> list[dict]:
        return await self._rows_post("rpc/card_issue_owners", {}, prefer="")

    async def fetch_owners_issued_since(self, since: datetime) -> set[str]:
        """그 시각 이후로 무료 카드를 이미 받은 사람. `card_issue_owners()` 는 "결정 안 한 카드가
        있는 사람"만 빼므로 오늘 수락·거절을 끝낸 사람은 배치를 다시 돌리면 또 대상이 된다 —
        Cloud Scheduler 재시도나 손으로 다시 돌릴 때 한 장이 더 나가는 걸 여기서 막는다."""
        rows = await self._rows("daily_cards", {
            "issued_at": f"gte.{since.isoformat()}", "source": "eq.daily", "select": "owner_id",
            "limit": _ISSUED_OWNERS_LIMIT,
        })
        if len(rows) == _ISSUED_OWNERS_LIMIT:
            logger.warning(
                "오늘 지급분 조회가 상한 %s 에 닿았다 — 이미 받은 사람이 빠져 카드가 두 번 나갈 수 있다",
                _ISSUED_OWNERS_LIMIT,
            )
        return {row["owner_id"] for row in rows}

    async def save_issue_weekdays(self, region_group: str, weekdays: list[int]) -> None:
        response = await self._patch(
            "region_group_settings",
            params={"region_group": f"eq.{region_group}"},
            json={"issue_weekdays": weekdays, "updated_at": "now()"},
        )
        raise_for_status(response)

    # 카드 ------------------------------------------------------------------
    async def insert_card(
        self, owner_id: UUID | str, target_id: UUID | str,
        expires_at: datetime | None, source: str = "daily",
    ) -> dict:
        rows = await self._rows_post("daily_cards", {
            "owner_id": str(owner_id), "target_id": str(target_id),
            "source": source, "expires_at": expires_at.isoformat() if expires_at else None,
        })
        return rows[0]

    async def fetch_live_cards(self, owner_id: UUID | str) -> list[dict]:
        """아직 결정하지 않았고 만료도 되지 않은 카드. 노출 순서는 설계 §2.4 대로
        [이번 주기 무료 → 이전 주기 구매] 다. card_source enum 이 ('daily','purchased') 순서로
        선언돼 있어 source 오름차순이 곧 [무료 → 구매]이고, 같은 source 안에서는 최근 것이 먼저다."""
        rows = await self._rows("daily_cards", {
            "owner_id": f"eq.{owner_id}",
            "select": "id,target_id,source,issued_at,expires_at,card_decisions(card_id)",
            "or": "(expires_at.is.null,expires_at.gt.now())",
            "order": "source.asc,issued_at.desc",
        })
        # card_decisions.card_id 가 PK 라 임베드는 배열이 아니라 객체/null 이다 — 결정이 없으면 null.
        return [row for row in rows if not row["card_decisions"]]

    async def fetch_card(self, card_id: UUID | str) -> dict | None:
        """card_decisions·acceptance_responses 는 card_id 가 PK 이자 daily_cards 참조라
        PostgREST 가 one-to-one 으로 보고 객체 하나(없으면 null)를 준다 — 목록이 아니다."""
        rows = await self._rows("daily_cards", {
            "id": f"eq.{card_id}",
            "select": "id,owner_id,target_id,source,issued_at,expires_at,"
                      "card_decisions(decision,decided_at),acceptance_responses(responder_id)",
        })
        return rows[0] if rows else None

    async def insert_decision(self, card_id: UUID | str, decision: str) -> None:
        await self._rows_post("card_decisions", {"card_id": str(card_id), "decision": decision}, prefer="")

    # 유료 카드 제안(paid_card_offers, 지시문 22) ---------------------------------------
    async def fetch_offered(self, owner_id: UUID | str) -> list[dict]:
        """아직 사지 않은 제안. 주기마다 최대 하나라 지난 주기에 남은 것까지 몇 줄뿐이다."""
        return await self._rows("paid_card_offers", {
            "owner_id": f"eq.{owner_id}", "status": "eq.offered", "select": _OFFER_COLUMNS,
        })

    async def has_purchased_since(self, owner_id: UUID | str, since: datetime) -> bool:
        """이번 주기에 이미 샀는가 — 샀으면 주기당 1장이라 새 제안을 만들지 않는다."""
        rows = await self._rows("paid_card_offers", {
            "owner_id": f"eq.{owner_id}", "status": "eq.purchased",
            "cycle_started_at": f"gte.{since.isoformat()}", "select": "id", "limit": 1,
        })
        return bool(rows)

    async def insert_offer(self, owner_id: UUID | str, cycle_started_at: datetime, target_id: UUID | str,
                           reasons: list[dict], band_count: int) -> dict:
        response = await self._post("paid_card_offers", json={
            "owner_id": str(owner_id), "cycle_started_at": cycle_started_at.isoformat(),
            "target_id": str(target_id), "reasons": reasons, "band_count": band_count,
            "status": "offered",  # DB 기본값에 기대지 않는다. created_at 은 DB 기본값에 맡긴다.
        }, prefer="return=representation")
        if response.status_code == 409 or error_code(response) == "23505":
            raise PaidOfferConflict()
        raise_for_status(response)
        return response.json()[0]

    async def set_offer_status(self, offer_id: UUID | str, status: str) -> None:
        """offered 인 것만 바꾼다 — 그사이 DB 가 purchased 로 바꿨으면 건드리지 않는다."""
        response = await self._patch(
            "paid_card_offers",
            params={"id": f"eq.{offer_id}", "status": "eq.offered"},
            json={"status": status},
        )
        raise_for_status(response)

    async def fetch_offer(self, offer_id: UUID | str) -> dict | None:
        rows = await self._rows("paid_card_offers", {"id": f"eq.{offer_id}", "select": _OFFER_COLUMNS})
        return rows[0] if rows else None

    async def fetch_purchased_reasons(self, card_ids: list[str]) -> dict[str, list[dict]]:
        """산 카드 → 그 카드를 만든 제안의 이유 태그(purchased_card_id 로 찾는다)."""
        if not card_ids:
            return {}
        rows = await self._rows("paid_card_offers", {
            "purchased_card_id": f"in.({','.join(card_ids)})", "select": "purchased_card_id,reasons",
        })
        return {row["purchased_card_id"]: row["reasons"] or [] for row in rows}

    async def purchase_paid_card(self, owner_id: UUID | str, offer_id: UUID | str) -> dict:
        """하트 차감 · daily_cards 생성 · 제안 purchased 처리를 DB 함수가 한 번에 한다(원자성은 DB 몫).
        5xx 는 그대로 올린다 — 서버가 반쪽 상태를 만들지 않는다."""
        response = await self._post("rpc/purchase_paid_card", json={
            "p_owner": str(owner_id), "p_offer": str(offer_id),
        })
        raise_for_status(response)
        return response.json()

    async def fetch_offer_target(self, profile_id: UUID | str) -> dict:
        rows = await self._rows("profiles", {"id": f"eq.{profile_id}", "select": _OFFER_TARGET_COLUMNS})
        return rows[0] if rows else {}

    async def fetch_interest_tags(self, profile_ids: list[str]) -> dict[str, list[str]]:
        """맞는 이유의 공통 관심 태그 이름. 후보 RPC 는 점수만 돌려줘서 이름은 따로 읽는다(새 제안을 만들 때만)."""
        rows = await self._rows("profiles", {
            "id": f"in.({','.join(str(i) for i in profile_ids)})", "select": "id,interest_tags",
        })
        return {row["id"]: row.get("interest_tags") or [] for row in rows}

    # 받은 수락함 -------------------------------------------------------------
    async def fetch_pending_acceptances(self, profile_id: UUID | str, days: int = 7,
                                        *, now: datetime) -> list[dict]:
        """내가 받은 수락 중 7일이 지나지 않았고 아직 답하지 않은 것(설계 §2.2, 2026-09-21 확정).
        건수가 1인당 하루 0.3~0.5건이라 응답 여부는 파이썬에서 거른다 — 전용 SQL 함수를 만들지 않는다.
        card_decisions 와 acceptance_responses 사이에는 FK 가 없어(둘 다 daily_cards 만 가리킨다)
        곧바로 임베드하면 PGRST200 이다 — daily_cards 를 거쳐서 붙인다."""
        since = now.astimezone(timezone.utc) - timedelta(days=days)
        rows = await self._rows("card_decisions", {
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
        await self._rows_post("acceptance_responses", {
            "card_id": str(card_id), "responder_id": str(responder_id), "decision": decision,
        }, prefer="")

    async def create_match(self, profile_a: UUID | str, profile_b: UUID | str) -> tuple[dict, bool]:
        """`(매칭 행, 이번에 새로 생겼나)`. C3 의 check (profile_a < profile_b) 를 지키려고
        여기서 한 번만 정렬한다. A→B, B→A 카드가 같은 날 나가면 두 사람이 각각 매칭을 만들려 해서
        두 번 들어오는데, 나중 쪽이 matches_pair_unique 로 터지면 안 된다.

        ignore-duplicates(= on conflict do nothing) 면 실제로 넣은 행만 돌아온다 — 빈 응답이 곧
        "이미 있었다" 라서 부른 쪽이 "매칭됐어요" 푸시를 두 번 보내지 않는다. 경합에도 안전하다."""
        first, second = sorted([str(profile_a), str(profile_b)])
        inserted = await self._rows_post(
            "matches", {"profile_a": first, "profile_b": second},
            prefer="resolution=ignore-duplicates,return=representation",
            params={"on_conflict": "profile_a,profile_b"},
        )
        if inserted:
            match = inserted[0]
        else:
            # 되읽기가 비는 경우는 그 사이에 매칭이 지워진 때뿐이다. 빈 목록을 그대로 [0] 하면
            # IndexError 가 500 으로 새어 나간다(조각 4 리뷰 권고 1번).
            rows = await self._rows("matches", {
                "profile_a": f"eq.{first}", "profile_b": f"eq.{second}", "select": "*",
            })
            if not rows:
                raise HTTPException(status_code=409, detail=errors.MATCH_CONFLICT)
            match = rows[0]
        await self._rows_post("match_participants", [
            {"match_id": match["id"], "profile_id": first},
            {"match_id": match["id"], "profile_id": second},
        ], prefer="resolution=merge-duplicates", params={"on_conflict": "match_id,profile_id"})
        return match, bool(inserted)

    # 프로필 요약 --------------------------------------------------------------
    async def fetch_card_profile(self, profile_id: UUID | str) -> dict:
        rows = await self._rows("profiles", {"id": f"eq.{profile_id}", "select": _CARD_PROFILE_COLUMNS})
        return rows[0] if rows else {}

    async def fetch_card_detail_profile(self, profile_id: UUID | str) -> dict:
        rows = await self._rows("profiles", {"id": f"eq.{profile_id}", "select": _CARD_DETAIL_COLUMNS})
        return rows[0] if rows else {}

    async def fetch_block_partner_ids(self, profile_id: UUID | str) -> set[str]:
        """내가 막았거나 나를 막은 사람(조각 6). 카드마다가 아니라 요청마다 한 번 읽는다.
        ponytail: 상한이 없다 — 한 사람의 차단이 db-max-rows(1000)를 넘으면 조용히 잘린다. 그때 RPC 로."""
        rows = await self._rows("blocks", {
            "or": f"(blocker_id.eq.{profile_id},blocked_id.eq.{profile_id})",
            "select": "blocker_id,blocked_id",
        })
        me = str(profile_id)
        return {row["blocked_id"] if row["blocker_id"] == me else row["blocker_id"] for row in rows}

    async def fetch_match_partner_ids(self, profile_id: UUID | str) -> set[str]:
        """이미 나와 매칭된 사람(결정 11). 수락함에서 뺀다 — A→B, B→A 를 둘 다 수락하면 매칭이 먼저 생긴다.
        ponytail: 상한이 없다 — 매칭이 db-max-rows(1000)를 넘으면 조용히 잘린다. 그때 RPC 로."""
        rows = await self._rows("matches", {
            "or": f"(profile_a.eq.{profile_id},profile_b.eq.{profile_id})",
            "select": "profile_a,profile_b",
        })
        me = str(profile_id)
        return {row["profile_b"] if row["profile_a"] == me else row["profile_a"] for row in rows}

    async def fetch_contact_block_partner_ids(self, profile_id: UUID | str, others: list[str]) -> set[str]:
        """others 중 지인 차단(어느 방향이든)으로 이어진 사람(결정 8 ②). 후보 SQL(match_candidates)과 같은 규칙 —
        번호 HMAC 과 키 버전이 둘 다 같아야 하고, 번호가 없는(phone_hmac null) 사람은 걸리지 않는다.
        차단 목록 전체가 아니라 화면에 나갈 others 만 묻는다 — 연락처 차단은 수백 줄일 수 있다."""
        me = str(profile_id)
        if not others:
            return set()
        phones = {row["profile_id"]: (row["phone_hmac"], row["phone_hmac_key_version"])
                  for row in await self._rows("profile_private", {
                      "profile_id": f"in.({','.join([me, *others])})",
                      "select": "profile_id,phone_hmac,phone_hmac_key_version",
                  }) if row["phone_hmac"]}
        hidden: set[str] = set()
        # ① 내가 막은 번호가 상대 번호다.
        their = {other: phones[other] for other in others if other in phones}
        if their:
            mine = {(row["contact_hmac"], row["key_version"]) for row in await self._rows("contact_blocks", {
                "owner_id": f"eq.{me}",
                "contact_hmac": f"in.({','.join(sorted({phone for phone, _ in their.values()}))})",
                "select": "contact_hmac,key_version",
            })}
            hidden |= {other for other, phone in their.items() if phone in mine}
        # ② 상대가 내 번호를 막았다.
        if me in phones:
            my_phone, my_version = phones[me]
            hidden |= {row["owner_id"] for row in await self._rows("contact_blocks", {
                "owner_id": f"in.({','.join(others)})",
                "contact_hmac": f"eq.{my_phone}", "key_version": f"eq.{my_version}",
                "select": "owner_id",
            })}
        return hidden

    async def fetch_survey(self, profile_id: UUID | str) -> list[float]:
        """9축을 번호 순서로. 답하지 않은 축은 0 이다 — 화면이 빈 칸 대신 가운데를 그린다."""
        rows = await self._rows("survey_answers", {
            "profile_id": f"eq.{profile_id}", "select": "axis,value",
        })
        answers = {int(row["axis"]): float(row["value"]) for row in rows}
        return [answers.get(axis, 0.0) for axis in SURVEY_AXES]

    async def fetch_region_group(self, profile_id: UUID | str) -> str | None:
        """지역그룹은 프로필이 아니라 학교가 들고 있다(universities.region_group)."""
        rows = await self._rows("profiles", {
            "id": f"eq.{profile_id}", "select": "universities(region_group)",
        })
        if not rows:
            return None
        return (rows[0].get("universities") or {}).get("region_group")

    # 푸시 · 알림 --------------------------------------------------------------
    async def upsert_push_token(self, token: str, profile_id: UUID | str, platform: str) -> None:
        await self._rows_post("push_tokens", {
            "token": token, "profile_id": str(profile_id), "platform": platform, "updated_at": "now()",
        }, prefer="resolution=merge-duplicates")

    async def delete_push_token(self, token: str, profile_id: UUID | str) -> None:
        """주인까지 맞아야 지운다 — 토큰 값만 보면 남의 기기 알림을 끌 수 있다."""
        response = await self._delete("push_tokens", params={
            "token": f"eq.{token}", "profile_id": f"eq.{profile_id}",
        })
        raise_for_status(response)

    # 밤에 보류된 알림(결정 4) — push.notify 가 넣고 push.send_pending 이 아침에 꺼내 지운다.
    async def insert_pending_push(self, profile_id: UUID | str, kind: str, title: str, body: str,
                                  data: dict[str, str]) -> None:
        await self._rows_post("pending_pushes", {
            "profile_id": str(profile_id), "kind": kind, "title": title, "body": body, "data": data,
        }, prefer="return=minimal")

    async def fetch_pending_pushes(self) -> list[dict]:
        # ponytail: PostgREST 한 번에 최대 1000행. 넘치면 나머지는 다음 시각 배치가 보낸다.
        return await self._rows("pending_pushes", {
            "select": "id,profile_id,kind,title,body,data", "order": "created_at",
        })

    async def delete_pending_pushes(self, ids: list[str]) -> None:
        response = await self._delete("pending_pushes", params={"id": f"in.({','.join(ids)})"})
        raise_for_status(response)

    async def fetch_profile_status(self, profile_id: UUID | str) -> str | None:
        """푸시 관문(push.notify)이 정지 계정을 거르는 데 쓴다. 행이나 칸이 없으면 None(= 막지 않는다,
        로그인 관문과 같은 규칙)."""
        rows = await self._rows("profiles", {"id": f"eq.{profile_id}", "select": "status"})
        return rows[0].get("status") if rows else None

    async def fetch_push_tokens(self, profile_id: UUID | str) -> list[str]:
        rows = await self._rows("push_tokens", {"profile_id": f"eq.{profile_id}", "select": "token"})
        return [row["token"] for row in rows]

    async def fetch_notification_settings(self, profile_id: UUID | str) -> dict:
        rows = await self._rows("notification_settings", {
            "profile_id": f"eq.{profile_id}", "select": _NOTIFICATION_COLUMNS,
        })
        return rows[0] if rows else {"profile_id": str(profile_id), **NOTIFICATION_DEFAULTS}

    async def update_notification_settings(self, profile_id: UUID | str, **fields) -> None:
        await self._rows_post("notification_settings", {
            "profile_id": str(profile_id), **fields,
        }, prefer="resolution=merge-duplicates")

    async def fetch_matching_paused(self, profile_id: UUID | str) -> bool:
        rows = await self._rows("profiles", {"id": f"eq.{profile_id}", "select": "matching_paused"})
        return bool(rows and rows[0].get("matching_paused"))

    async def set_matching_paused(self, profile_id: UUID | str, paused: bool) -> None:
        response = await self._patch(
            "profiles",
            params={"id": f"eq.{profile_id}"},
            json={"matching_paused": paused},
        )
        raise_for_status(response)
