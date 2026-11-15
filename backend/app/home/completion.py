"""홈 09b 프로필 완성도(2026-09-26 사용자 확정): 기본 60 + 아래 넷을 채울 때마다 10, 최대 100.

온보딩 필수값은 이미 다 채운 사람만 홈에 오므로 60 에서 시작한다. 넷은 "더 채울 수 있는 것"이다.
"""
BASE_PERCENT = 60
STEP_PERCENT = 10
MIN_PHOTOS = 3
FULL_TAGS = 5


# 넷의 순서 = 앱 칩 순서(2026-11-15 사용자 「~더 채우기 칩」). 이름은 앱이 enum 으로 읽는 값 그대로다.
ITEMS = ("photos", "mbti", "preferred_height", "interest_tags")


def completion_missing(*, photo_count: int, mbti: str | None, preferred_height_min: int | None,
                       preferred_height_max: int | None, interest_tags: list[str] | None) -> list[str]:
    """아직 안 채운 항목을 [ITEMS] 순서로. 퍼센트도 이것으로 센다 — 조건은 이 한 곳에만 있다."""
    filled = (
        photo_count >= MIN_PHOTOS,
        mbti is not None,
        preferred_height_min is not None or preferred_height_max is not None,
        len(interest_tags or []) == FULL_TAGS,
    )
    return [item for item, done in zip(ITEMS, filled) if not done]


def completion_percent(**materials) -> int:
    return BASE_PERCENT + STEP_PERCENT * (len(ITEMS) - len(completion_missing(**materials)))
