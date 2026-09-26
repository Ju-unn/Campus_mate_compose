"""홈 09b 프로필 완성도(2026-09-26 사용자 확정): 기본 60 + 아래 넷을 채울 때마다 10, 최대 100.

온보딩 필수값은 이미 다 채운 사람만 홈에 오므로 60 에서 시작한다. 넷은 "더 채울 수 있는 것"이다.
"""
BASE_PERCENT = 60
STEP_PERCENT = 10
MIN_PHOTOS = 3
FULL_TAGS = 5


def completion_percent(*, photo_count: int, mbti: str | None, preferred_height_min: int | None,
                       preferred_height_max: int | None, interest_tags: list[str] | None) -> int:
    filled = [
        photo_count >= MIN_PHOTOS,
        mbti is not None,
        preferred_height_min is not None or preferred_height_max is not None,
        len(interest_tags or []) == FULL_TAGS,
    ]
    return BASE_PERCENT + STEP_PERCENT * sum(filled)
