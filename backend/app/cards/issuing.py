import logging
import random
from datetime import datetime, time

from app.cards.ladder import bottleneck_count, ladder_weekdays, last_issue_at, next_issue_at
from app.cards.paid_offer import ensure_offer
from app.cards.push import notify
from app.matching.band import FREE_BAND_RATIO, pick_from_band, rank_all

logger = logging.getLogger(__name__)


def _parse_time(value: str) -> time:
    return time.fromisoformat(value)


async def issue_daily_cards(card_repo, matching_repo, sender, now: datetime,
                            rng: random.Random | None = None) -> dict:
    """하루 한 번 도는 지급 배치(설계 §2.1). Cloud Scheduler 가 07:00 Asia/Seoul 에 부른다.

    대상자마다 ① 이번 주기의 유료 카드 제안을 먼저 확보하고 ② 그 사람을 빼고 무료 카드를 상위 80% 구간에서
    무작위로 뽑는다(지시문 22). rng 는 시험이 시드를 고정하려고 받는다.

    ponytail: 대상자마다 RPC 2번(프로필 + 후보)과 유료 제안 읽기 2번 · 쓰기 1~2번(새로 정할 때 태그 이름 읽기 포함)을 부른다. 서울 한 그룹 · 수백 명 규모에서는 충분하고,
    수천 명이 되면 후보 조회를 한 번에 모아 오는 SQL 로 바꾼다(백로그)."""
    rng = rng or random.Random()
    settings_by_region = {row["region_group"]: row for row in await card_repo.fetch_region_settings()}
    counts = await card_repo.fetch_active_counts()

    weekdays_by_region: dict[str, list[int]] = {}
    skipped: list[str] = []
    for region, row in settings_by_region.items():
        weekdays = ladder_weekdays(
            bottleneck_count(counts.get(region, {})),
            row["ladder_twice_per_week_min"], row["ladder_three_per_week_min"],
            row["ladder_four_per_week_min"], row["ladder_daily_min"],
        )
        if weekdays != list(row["issue_weekdays"]):
            # 사다리 결과를 설정 행에 적어 둔다 — 앱이 "다음 지급은 O요일" 문구를 여기서 읽는다.
            await card_repo.save_issue_weekdays(region, weekdays)
        weekdays_by_region[region] = weekdays
        if now.isoweekday() not in weekdays:
            skipped.append(region)

    # 오늘 이미 받은 사람은 건너뛴다 — 배치를 두 번 돌려도 하루 한 장이다.
    issued_today = await card_repo.fetch_owners_issued_since(
        now.replace(hour=0, minute=0, second=0, microsecond=0)
    )

    issued = 0
    no_candidate = 0
    for owner in await card_repo.fetch_issue_owners():
        region = owner["region_group"]
        weekdays = weekdays_by_region.get(region)
        if weekdays is None or now.isoweekday() not in weekdays:
            continue

        owner_id = owner["profile_id"]
        if owner_id in issued_today:
            continue
        owner_row = await matching_repo.fetch_owner(owner_id)
        # 후보는 이미 본 사람까지 전부다(pickable 칸) — 구간은 전체로 재고 뽑을 때만 pickable 을 본다.
        ranked = rank_all(owner_row, await matching_repo.fetch_candidates(owner_id))
        issue_time = _parse_time(settings_by_region[region]["issue_time"])

        # ① 유료 제안은 무료 카드가 나가든 말든 확보한다. ② 그 사람은 무료 카드에서 뺀다.
        offer = await ensure_offer(card_repo, owner_row, ranked, last_issue_at(now, weekdays, issue_time),
                                   rng, now)
        exclude = frozenset({str(offer["target_id"])}) if offer else frozenset()
        picked = pick_from_band(ranked, FREE_BAND_RATIO, rng, exclude=exclude)
        if picked is None:
            # 구간에 뽑을 사람이 없으면 이번 주기에는 카드가 없다 — 화면 11b `iQZoa` 가 이 상태를 설명한다.
            no_candidate += 1
            continue

        expires_at = next_issue_at(now, weekdays, issue_time)
        card = await card_repo.insert_card(owner_id, picked["candidate_id"], expires_at)
        issued += 1

        if sender is not None:
            try:
                await notify(
                    card_repo, sender, owner_id, "card_arrived",
                    "오늘의 카드가 도착했어요", "지금 확인해 보세요",
                    {"route": "daily_card", "card_id": str(card["id"])}, now=now,
                )
            except Exception:
                # 카드는 이미 들어갔다. 알림 한 건 때문에 뒷사람 지급까지 멈추는 쪽이 훨씬 나쁘다.
                logger.exception("카드 도착 알림 실패 owner=%s", owner_id)

    return {"issued": issued, "no_candidate": no_candidate, "skipped_regions": skipped}
