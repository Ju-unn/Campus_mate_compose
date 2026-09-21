"""앱 전체가 같은 한국 시각을 보게 하는 시간대 하나.

원래 profile_onboarding.schemas 에 있어서 카드·매칭이 상관없는 온보딩 모듈을 거쳐 가져다 썼다.
"""
from datetime import timedelta, timezone

# 서버 시계가 UTC 라도 날짜는 한국 기준으로 세야 12월 31일 밤에 기준이 하루 어긋나지 않는다.
# 한국은 서머타임이 없어 고정 +9 로 충분하다(zoneinfo 는 윈도우에서 tzdata 패키지를 더 요구한다).
SEOUL = timezone(timedelta(hours=9))
