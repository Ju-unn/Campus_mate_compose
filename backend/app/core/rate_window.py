"""사람당 최근 시각을 세는 속도 제한(슬라이딩 창). 지인 리뷰 친구 코드(friend_reviews)에서 옮겨 왔다 — 사진 검사(Vision)
하루 상한도 같이 쓴다(10-18 보안 점검)."""
from datetime import datetime, timedelta

from fastapi import HTTPException


class SlidingWindow:
    """사용자당 최근 span 안의 시각, limit 개까지(슬라이딩 창). hold 는 await 없이 자리를 먼저 잡고(꽉 찼으면 429 + detail)
    일이 안 되면 release 로 돌려준다 — 동시에 여러 요청이 와도 한도를 넘지 못한다. 막힌(429) 시도는 세지 않아
    두드려도 창이 밀리지 않는다. span 이 지난 사람은 hold 때마다 지워 메모리가 늘지 않는다.
    shortcut: 프로세스 안 dict 라 한도가 인스턴스별이다 — Cloud Run 이 N 대로 늘면 N 배까지 느슨해지고 재시작하면
    비워진다. 한도가 실제로 뚫리면 DB 카운터(시각 행 + 시간 인덱스)로 올린다."""

    def __init__(self, limit: int, span: timedelta, detail: str):
        self.limit, self.span, self.detail = limit, span, detail
        self.times: dict[str, list[datetime]] = {}

    def hold(self, me: str, now: datetime) -> None:
        cutoff = now - self.span
        for key in [key for key, times in self.times.items() if not times or times[-1] <= cutoff]:
            del self.times[key]
        times = [t for t in self.times.get(me, []) if t > cutoff]
        if len(times) >= self.limit:
            self.times[me] = times
            raise HTTPException(status_code=429, detail=self.detail)
        self.times[me] = [*times, now]

    def release(self, me: str, now: datetime) -> None:
        times = self.times.get(me)
        if times and now in times:
            times.remove(now)
