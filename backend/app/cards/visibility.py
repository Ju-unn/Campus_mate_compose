"""상대가 카드 화면에서 사라져야 하는가(조각 6). 카드 라우터와 유료 카드 제안(paid_offer)이 같은 판정을 쓴다 —
router 에 두면 paid_offer 가 router 를 import 해야 해서(router 도 paid_offer 를 부른다) 여기로 옮겼다."""


def is_active(profile: dict) -> bool:
    """정지 · 탈퇴 · 가입 중이 아닌가. 14c 상대 프로필(safety)도 같은 판정을 쓴다.
    status 칸이 없는 행은 active 로 읽는다 — 로그인 관문이 status 없는 행을 통과시키는 것과 같은 규칙이다."""
    return profile.get("status", "active") == "active"


def hidden_from_cards(other_id: str, profile: dict, blocked: set[str]) -> bool:
    """상대가 내 카드 화면에서 사라져야 하는가(조각 6) — 차단 · 지인 차단(어느 방향이든) · 정지 · 탈퇴 · 자동 가림.

    후보 SQL(PR 1)은 새 카드가 나가는 것을 막고, 여기는 **이미 나간 카드와 받은 수락**을 막는다 —
    차단한 상대의 수락을 눌러 매칭이 생기면 안 된다. 오늘 카드 · 카드 상세 · 결정 · 수락함 · 수락 응답 ·
    유료 카드 제안이 같이 쓴다."""
    return other_id in blocked or not is_active(profile) or bool(profile.get("auto_hidden_at"))
