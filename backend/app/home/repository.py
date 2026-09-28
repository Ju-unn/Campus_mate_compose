from datetime import datetime, timedelta, timezone
from uuid import UUID

from app.core.http import raise_for_status
from app.core.postgrest import PostgrestRepository

# 카드 자격(14일) · 후보(15일)는 일 단위라 한 시간 정밀도면 충분하다.
_TOUCH_INTERVAL = timedelta(hours=1)


class HomeRepository(PostgrestRepository):
    """홈 09b 가 읽는 두 가지. 서비스 전체 집계는 DB 함수 한 번(`home_stats`), 내 완성도 재료는
    profiles 한 줄 + 사진 개수 embed 로 한 번(학교 여는 시각도 같이). 학교가 아직 안 열렸을 때만
    모집 인원을 한 번 더 센다(19 코호트). 쓰기는 활동 시각 하나뿐이다."""

    async def fetch_stats(self) -> dict:
        # 단일 행 테이블 함수라 PostgREST 는 한 행짜리 배열로 준다.
        response = await self._post("rpc/home_stats", json={})
        raise_for_status(response)
        return response.json()[0]

    async def fetch_completion_materials(self, profile_id: UUID) -> dict:
        response = await self._get("profiles", params={
            "id": f"eq.{profile_id}",
            "select": "mbti,preferred_height_min,preferred_height_max,interest_tags,profile_photos(count),"
                      "university_id,universities(card_opens_at)",
        })
        raise_for_status(response)
        return response.json()[0]

    async def count_recruits(self, university_id: str) -> int:
        # 모집 인원 = 그 학교에서 가입을 끝낸 사람(홈 "가입 수"와 같은 기준, 코호트 계획서 결정 3).
        response = await self._client.get(
            f"{self._postgrest_url}/profiles",
            params={"university_id": f"eq.{university_id}", "status": "eq.active", "select": "id", "limit": 1},
            headers=self._with_prefer("count=exact"),
        )
        raise_for_status(response)
        # Content-Range: 0-0/37 (없으면 */0) — 전체 건수는 / 뒤다.
        return int(response.headers["content-range"].rsplit("/", 1)[1])

    async def touch_last_active(self, profile_id: UUID) -> None:
        """활동 시각이 한 시간보다 오래됐을 때만 지금으로 바꾼다. 조건을 PostgREST 필터에 걸어
        읽고-비교하고-쓰는 사이 경쟁이 없고, 한 시간 안에 다시 열면 0행 갱신이라 쓰기가 거의 없다."""
        now = datetime.now(timezone.utc)
        response = await self._patch("profiles", params={
            "id": f"eq.{profile_id}",
            "last_active_at": f"lt.{(now - _TOUCH_INTERVAL).isoformat()}",
        }, json={"last_active_at": now.isoformat()}, prefer="return=minimal")
        raise_for_status(response)
