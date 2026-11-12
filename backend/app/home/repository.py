from datetime import datetime, timedelta, timezone
from uuid import UUID

from app.core.http import raise_for_status
from app.core.postgrest import PostgrestRepository

# 카드 자격(14일) · 후보(15일)는 일 단위라 한 시간 정밀도면 충분하다.
_TOUCH_INTERVAL = timedelta(hours=1)
# 홈 배너는 몇 장만 돈다 — 운영 실수로 줄이 많이 쌓여도 홈 응답이 커지지 않게 자른다.
_BANNER_LIMIT = 10


class HomeRepository(PostgrestRepository):
    """홈 09b 가 읽는 것. 서비스 전체 집계는 DB 함수 한 번(`home_stats`), 내 완성도 재료는
    profiles 한 줄 + 사진 개수 embed 로 한 번(학교 여는 시각도 같이). 학교가 아직 안 열렸을 때만
    모집 인원을 한 번 더 센다(19 코호트). 레일 사람들(/home/people)은 따로 한 번 읽는다. 쓰기는 활동 시각 하나뿐이다."""

    async def fetch_stats(self) -> dict:
        # 단일 행 테이블 함수라 PostgREST 는 한 행짜리 배열로 준다.
        response = await self._post("rpc/home_stats", json={})
        raise_for_status(response)
        return response.json()[0]

    async def fetch_banners(self, now: datetime) -> list[dict]:
        """지금 기간 안의 홈 배너(starts_at <= now, ends_at 이 비었거나 > now)를 sort_order · created_at 순으로 많아야 10장.
        image_path · alt_text 만 읽는다. 시각 값에 `:` · `.` 이 들어 있어 or 안에서는 따옴표로 감싼다(PostgREST 예약 문자)."""
        at = now.isoformat()
        response = await self._get("home_banners", params={
            "select": "image_path,alt_text",
            "starts_at": f"lte.{at}",
            "or": f'(ends_at.is.null,ends_at.gt."{at}")',
            "order": "sort_order.asc,created_at.asc",
            "limit": _BANNER_LIMIT,
        })
        raise_for_status(response)
        return response.json()

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

    async def fetch_my_gender(self, profile_id: UUID) -> str | None:
        """내 성별('male' | 'female'). 비어 있거나 행이 없으면 None — 부른 쪽이 빈 레일로 처리한다."""
        response = await self._get("profiles", params={"id": f"eq.{profile_id}", "select": "gender"})
        raise_for_status(response)
        rows = response.json()
        return rows[0]["gender"] if rows else None

    async def fetch_recent_people(self, profile_id: UUID, limit: int, gender: str) -> list[dict]:
        """홈 레일 후보 — 최근에 활동한 순으로 limit 명(모든 학교, gender 로 준 성별만, 나는 빼고). 보여 줄 수 있는 사람
        (가입을 마쳤고 자동 가림이 아니고 매칭을 멈추지 않은)만 DB 가 거르고, 아바타 고르기 · 차단은 부른 쪽이 한다.
        성별도 DB 가 걸러 풀(limit)이 그 성별 사람으로 채워진다 — 나중에 거르면 풀이 줄어 레일이 자주 빈다. gender 는
        'male' | 'female' 중 하나여야 한다(필터 문자열에 그대로 들어가므로 부른 쪽이 내 성별에서 뽑은 값만 넘긴다).
        매칭을 멈춘 사람은 지금 사람을 만나지 않겠다는 뜻이라 홈에도 얼굴을 내보내지 않는다(안전한 쪽, 2026-10-15 검토).
        시험 학교(`universities.region_group = 'e2e'`, 심사 · 시험 계정)의 사람은 누구의 레일에도 내보내지 않는다(사용자 결정 2026-11-12,
        숫자 · 대학 칩과 같은 규칙). `universities!inner()` 가 학교 표를 끼우기만 하고 칸은 읽지 않는다 — 학교 없는 프로필(학교 메일 인증 전 —
        인증 칸은 학교가 있어야 채워진다)은 같이 빠지는데, 그 사람은 아직 앱 본문을 쓰지 못해 레일에 나올 사람이 아니다.
        id 와 아바타 행 말고는 읽지 않는다 — 응답에 실을 칸이 없다.
        ponytail: last_active_at 인덱스가 없어 profiles 를 훑고 상위 limit 개를 정렬한다. 가입자가 수만 명이 되면
        `(last_active_at desc) where status='active' and auto_hidden_at is null and not matching_paused` 부분 인덱스로."""
        response = await self._get("profiles", params={
            "status": "eq.active", "auto_hidden_at": "is.null", "matching_paused": "is.false",
            "gender": f"eq.{gender}", "id": f"neq.{profile_id}", "universities.region_group": "neq.e2e",
            "select": "id,profile_avatars(storage_path,status,is_fallback,created_at),universities!inner()",
            "order": "last_active_at.desc", "limit": limit,
        })
        raise_for_status(response)
        return response.json()

    async def fetch_blocked_among(self, profile_id: UUID, others: list[str]) -> set[str]:
        """others 중 나와 차단으로 이어진 사람(어느 방향이든). 내 차단 전부(cards fetch_block_partner_ids)를 읽으면
        db-max-rows(1000)에서 조용히 잘려 그 뒤의 차단 상대가 레일에 뜬다 — others 로만 물어 많아야 2×len(others) 줄이다."""
        if not others:
            return set()
        me, ids = str(profile_id), ",".join(others)
        response = await self._get("blocks", params={
            "or": f"(and(blocker_id.eq.{me},blocked_id.in.({ids})),and(blocked_id.eq.{me},blocker_id.in.({ids})))",
            "select": "blocker_id,blocked_id",
        })
        raise_for_status(response)
        return {row["blocked_id"] if row["blocker_id"] == me else row["blocker_id"] for row in response.json()}

    async def touch_last_active(self, profile_id: UUID) -> None:
        """활동 시각이 한 시간보다 오래됐을 때만 지금으로 바꾼다. 조건을 PostgREST 필터에 걸어
        읽고-비교하고-쓰는 사이 경쟁이 없고, 한 시간 안에 다시 열면 0행 갱신이라 쓰기가 거의 없다."""
        now = datetime.now(timezone.utc)
        response = await self._patch("profiles", params={
            "id": f"eq.{profile_id}",
            "last_active_at": f"lt.{(now - _TOUCH_INTERVAL).isoformat()}",
        }, json={"last_active_at": now.isoformat()}, prefer="return=minimal")
        raise_for_status(response)
