"""유료 카드 제안(paid_card_offers)을 메모리에서 흉내 내는 가짜 저장소 — 지급 배치 · ensure_offer 시험이 같이 쓴다.

DB 계약(지시문 22): 같은 owner 에 status='offered' 는 cycle_started_at 마다 하나(부분 유일 인덱스) — 두 번째
insert 는 PostgREST 409 이고, 저장소는 이를 PaidOfferConflict 로 바꿔 올린다. 여기서도 같은 규칙을 지킨다."""
from datetime import datetime

from app.cards.repository import PaidOfferConflict


def candidate(candidate_id: str, trait_score: float, pickable: bool = True, **overrides) -> dict:
    """match_candidates 한 줄 — 지금 칸 전부 + pickable(DB 계약 1)."""
    return {"candidate_id": candidate_id, "trait_score": trait_score, "tag_score": 0.0,
            "text_score": 0.0, "mbti": None, "preferred_mbti_flags": {}, "height_cm": 165,
            "preferred_height_min": None, "preferred_height_max": None, "birth_year": 2003,
            "preferred_age_min": None, "preferred_age_max": None, "is_smoker": False,
            "religion": "none", "last_active_at": "2026-09-21T00:00:00+00:00",
            "pickable": pickable, **overrides}


def owner_row(owner_id: str = "owner-1", **overrides) -> dict:
    return {"id": owner_id, "status": "active", "gender": "male", "mbti": None,
            "preferred_mbti_flags": {}, "height_cm": 180, "preferred_height_min": None,
            "preferred_height_max": None, "birth_year": 2002, "preferred_age_min": None,
            "preferred_age_max": None, "is_smoker": False, "religion": "none", **overrides}


class OfferStore:
    """paid_card_offers 표 + 대상 자격 판정에 필요한 프로필 · 차단 읽기."""

    def __init__(self, offers=None, hidden_profiles=None, blocked=(), tags=None):
        self.offers: list[dict] = [dict(o) for o in (offers or [])]
        self.hidden_profiles: dict[str, dict] = hidden_profiles or {}
        self.blocked: set[str] = set(blocked)
        self.tags: dict[str, list[str]] = tags or {}
        self.inserts = 0
        self.conflict_once: dict | None = None  # 동시 요청 흉내 — 다음 insert 직전에 이 행이 먼저 들어간다.
        self.target_reads = 0

    async def fetch_offered(self, owner_id):
        return [dict(o) for o in self.offers if o["owner_id"] == owner_id and o["status"] == "offered"]

    async def has_purchased_since(self, owner_id, since):
        return any(o["owner_id"] == owner_id and o["status"] == "purchased"
                   and datetime.fromisoformat(o["cycle_started_at"]) >= since for o in self.offers)

    async def insert_offer(self, owner_id, cycle_started_at, target_id, reasons, band_count):
        if self.conflict_once is not None:
            self.offers.append(self.conflict_once)
            self.conflict_once = None
        cycle = cycle_started_at.isoformat()
        if any(o["owner_id"] == owner_id and o["status"] == "offered"
               and datetime.fromisoformat(o["cycle_started_at"]) == cycle_started_at for o in self.offers):
            raise PaidOfferConflict()
        self.inserts += 1
        row = {"id": f"offer-{len(self.offers)}", "owner_id": owner_id, "cycle_started_at": cycle,
               "target_id": target_id, "reasons": reasons, "band_count": band_count,
               "status": "offered", "purchased_card_id": None}
        self.offers.append(row)
        return dict(row)

    async def set_offer_status(self, offer_id, status):
        for o in self.offers:
            if o["id"] == offer_id and o["status"] == "offered":
                o["status"] = status

    async def fetch_offer_target(self, profile_id):
        self.target_reads += 1
        return {"id": profile_id, "status": "active", "auto_hidden_at": None, "matching_paused": False,
                "profile_avatars": [], **self.hidden_profiles.get(profile_id, {})}

    async def fetch_block_partner_ids(self, profile_id):
        return set(self.blocked)

    async def fetch_contact_block_partner_ids(self, profile_id, others):
        return set()

    async def fetch_interest_tags(self, profile_ids):
        return {pid: list(self.tags.get(pid, [])) for pid in profile_ids}

    def by_status(self, status: str) -> list[dict]:
        return [o for o in self.offers if o["status"] == status]
