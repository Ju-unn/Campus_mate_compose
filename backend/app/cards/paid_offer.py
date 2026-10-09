"""유료 카드 제안(지시문 22, 설계 「01_설계_카드선정_유료카드」 사용자 승인).

지급 주기마다 한 사람을 **미리** 정한다 — 상위 20% 구간 중 pickable 인 사람에서 균등 무작위. 이 사람은 그 주기의
무료 카드에서 빠진다. 사지 않으면 다음 주기에 새로 정하고, 정해 둔 사람이 자격을 잃으면 그 자리에서 새로 정한다.
구매(하트 차감 · 카드 생성)는 DB 함수 rpc/purchase_paid_card 가 한 번에 한다 — 여기는 제안만 다룬다."""
import random
from datetime import datetime

from app.cards.repository import PaidOfferConflict
from app.cards.visibility import hidden_from_cards
from app.matching.band import PAID_BAND_RATIO, band_size, pick_from_band
from app.matching.scoring import mbti_coefficient, profile_age, range_coefficient

# 유료 카드 한 장 값(하트). 실제 차감은 DB 함수가 한다 — 이 값은 화면에 보여 줄 가격이다(DB 와 같은 값이어야 한다).
PAID_CARD_COST = 50
# 맞는 이유로 말할 만큼 강한가의 문턱(0~1). 지시문 22 D: 모호하면 0.5 로 시작하고 PR 에 적는다.
REASON_THRESHOLD = 0.5
MAX_REASONS = 3
MAX_TAG_NAMES = 2
# 나열 순서가 곧 동점일 때의 순서다.
REASON_KINDS = ("tendency", "tags", "ideal", "mbti", "age_height", "smoke_religion")
_FIXED_TEXTS = {
    "tendency": "성향이 비슷해요",
    "ideal": "'이런 사람이 좋아요'와 잘 맞아요",
    "mbti": "MBTI가 잘 맞아요",
    "age_height": "나이·키가 원하는 범위예요",
    "smoke_religion": "흡연·종교 조건이 맞아요",
}
_RANGE_KEYS = ("preferred_height_min", "preferred_height_max", "preferred_age_min", "preferred_age_max")
# 계수는 곱셈 결과라 1.0 이 부동소수 오차로 0.9999… 가 될 수 있다.
_NO_PENALTY = 1.0 - 1e-9


def _subject_particle(word: str) -> str:
    """'#러닝이' · '#카페가' — 마지막 글자에 받침이 있으면 '이'. 한글이 아니면(예: IT) '가'."""
    last = word[-1]
    if "가" <= last <= "힣":
        return "이" if (ord(last) - ord("가")) % 28 else "가"
    return "가"


def _common_tags(owner: dict, target: dict) -> list[str]:
    """공통 관심 태그 이름. 내 태그 순서를 따라 최대 MAX_TAG_NAMES 개."""
    theirs = set(target.get("interest_tags") or [])
    return [tag for tag in owner.get("interest_tags") or [] if tag in theirs][:MAX_TAG_NAMES]


def _strengths(owner: dict, target: dict, tags: list[str]) -> dict[str, float]:
    """요소마다 0~1. 점수 세 가지(scoring.final_score 의 trait · tag · text)는 그대로, 계수 세 가지는
    불이익 없이(계수 1.0) 맞고 말할 근거가 있을 때만 1.0 이다 — MBTI 가 없거나 범위를 아무도 두지 않았으면
    계수가 1.0 이어도 "맞아요" 라고 하지 않는다."""
    mbti_ok = bool(owner.get("mbti") and target.get("mbti")) and mbti_coefficient(
        owner.get("preferred_mbti_flags") or {}, target["mbti"],
        target.get("preferred_mbti_flags") or {}, owner["mbti"],
    ) >= _NO_PENALTY
    age_height_ok = any(p.get(k) is not None for p in (owner, target) for k in _RANGE_KEYS) and (
        range_coefficient(
            owner.get("height_cm"), owner.get("preferred_height_min"), owner.get("preferred_height_max"),
            target.get("height_cm"), target.get("preferred_height_min"), target.get("preferred_height_max"),
            near=5,
        ) * range_coefficient(
            profile_age(owner), owner.get("preferred_age_min"), owner.get("preferred_age_max"),
            profile_age(target), target.get("preferred_age_min"), target.get("preferred_age_max"),
            near=2,
        )
    ) >= _NO_PENALTY
    # scoring.final_score 의 흡연(0.5) · 종교(0.8) 감점과 같은 조건이다.
    smoke_religion_ok = not (owner.get("is_smoker") is False and target.get("is_smoker") is True) \
        and owner.get("religion") == target.get("religion")
    return {
        "tendency": float(target.get("trait_score") or 0),
        "tags": float(target.get("tag_score") or 0) if tags else 0.0,
        "ideal": float(target.get("text_score") or 0),
        "mbti": 1.0 if mbti_ok else 0.0,
        "age_height": 1.0 if age_height_ok else 0.0,
        "smoke_religion": 1.0 if smoke_religion_ok else 0.0,
    }


def build_reasons(owner_row: dict, target_candidate: dict) -> list[dict]:
    """맞는 이유 태그 최대 3개 `[{"kind", "text"}]`. 강한 순, 동점이면 REASON_KINDS 순서, 문턱 미만은 뺀다.

    text 에는 학교 이름 · 궁합 점수 숫자 · "이상형 조건에 맞는" 문구 · 이름 · 닉네임을 넣지 않는다(결제 전에
    사람이 드러나지 않게). 태그 이름은 관심 태그 목록의 고정 문구라 사람을 가리키지 않는다."""
    tags = _common_tags(owner_row, target_candidate)
    strengths = _strengths(owner_row, target_candidate, tags)
    chosen = [kind for kind in REASON_KINDS if strengths[kind] >= REASON_THRESHOLD]
    chosen.sort(key=lambda kind: -strengths[kind])  # 안정 정렬 — 동점은 나열 순서가 남는다
    reasons = []
    for kind in chosen[:MAX_REASONS]:
        if kind == "tags":
            names = " ".join(f"#{tag}" for tag in tags)
            text = f"{names}{_subject_particle(tags[-1])} 같아요"
        else:
            text = _FIXED_TEXTS[kind]
        reasons.append({"kind": kind, "text": text})
    return reasons


async def target_eligible(card_repo, owner_id: str, target_id: str,
                          blocked: set[str] | None = None) -> tuple[bool, dict]:
    """정해 둔 사람이 아직 자격이 있는가 — 카드 화면과 같은 판정(차단 · 지인 차단 · 정지 · 탈퇴 · 자동 가림)에
    일시중지를 더한다. `(자격, 읽은 프로필)` — 프로필은 부른 쪽이 아바타 주소를 만들 때 다시 쓴다.
    blocked 를 주면 차단을 다시 읽지 않는다(GET /cards/today 는 요청마다 한 번 읽어 둔다)."""
    profile = await card_repo.fetch_offer_target(target_id)
    if not profile:
        return False, profile
    if blocked is None:
        blocked = await card_repo.fetch_block_partner_ids(owner_id) \
            | await card_repo.fetch_contact_block_partner_ids(owner_id, [target_id])
    eligible = not hidden_from_cards(target_id, profile, blocked) and not profile.get("matching_paused")
    return eligible, profile


def _cycle_of(offer: dict) -> datetime:
    return datetime.fromisoformat(offer["cycle_started_at"])


async def _current_offered(card_repo, owner_id: str, cycle_started_at: datetime) -> dict | None:
    for offer in await card_repo.fetch_offered(owner_id):
        if _cycle_of(offer) >= cycle_started_at:
            return offer
    return None


async def ensure_offer(card_repo, owner_row: dict, ranked: list[dict], cycle_started_at: datetime,
                       rng: random.Random, now: datetime, blocked: set[str] | None = None) -> dict | None:
    """이번 주기의 offered 제안을 돌려준다(없으면 만든다). 만들 사람이 없거나 이번 주기에 이미 샀으면 None.

    ranked 는 band.rank_all 로 매긴 **전체** 후보(이미 본 사람 포함)다 — 구간은 전체로 재고 pickable 은 뽑을
    때만 본다. 지급 배치와 GET /cards/today(살아 있는 제안이 없을 때만)가 부른다."""
    if cycle_started_at > now:
        raise ValueError(f"주기 시작이 지금보다 뒤다: {cycle_started_at} > {now}")
    owner_id = str(owner_row["id"])
    if await card_repo.has_purchased_since(owner_id, cycle_started_at):
        return None  # 주기당 1장

    by_id = {str(c["candidate_id"]): c for c in ranked}
    lost: set[str] = set()
    for offer in await card_repo.fetch_offered(owner_id):
        target_id = str(offer["target_id"])
        if _cycle_of(offer) < cycle_started_at:
            # 지난 주기에 안 산 제안 — 다음 주기에 새로 정한다.
            await card_repo.set_offer_status(offer["id"], "expired")
            continue
        # 후보 SQL 이 하드 필터로 뺐거나(차단 등) 더는 pickable 이 아니면(매칭됨 등) 이미 자격을 잃은 것이다.
        candidate = by_id.get(target_id)
        if candidate is not None and candidate["pickable"] \
                and (await target_eligible(card_repo, owner_id, target_id, blocked))[0]:
            return offer  # 같은 주기에 다시 열어도 같은 사람
        await card_repo.set_offer_status(offer["id"], "replaced")
        lost.add(target_id)

    exclude = frozenset(lost)
    pick = pick_from_band(ranked, PAID_BAND_RATIO, rng, exclude=exclude)
    if pick is None:
        return None  # 비어 있음 — 구매도 막힌다
    band = ranked[: band_size(len(ranked), PAID_BAND_RATIO)]
    band_count = sum(1 for c in band if c["pickable"] and str(c["candidate_id"]) not in exclude)

    target_id = str(pick["candidate_id"])
    tags = await card_repo.fetch_interest_tags([owner_id, target_id])
    reasons = build_reasons({**owner_row, "interest_tags": tags.get(owner_id, [])},
                            {**pick, "interest_tags": tags.get(target_id, [])})
    try:
        return await card_repo.insert_offer(owner_id, cycle_started_at, target_id, reasons, band_count)
    except PaidOfferConflict:
        # 동시 요청(배치와 화면 열기가 겹침)이 먼저 넣었다 — 그것을 쓴다.
        return await _current_offered(card_repo, owner_id, cycle_started_at)
