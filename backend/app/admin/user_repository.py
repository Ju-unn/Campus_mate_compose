"""관리자 사용자 화면(설계 10-18 §8-3)의 DB 호출. 읽기는 PostgREST, 바꾸는 일은 DB 함수 하나(한 트랜잭션, 마이그레이션 20261018120000).

학교 메일은 원문을 받지 않는다 — 부르는 쪽이 해시(`\\x…` 리터럴)만 넘긴다."""
import asyncio
import re
from uuid import UUID

from app.admin.paging import Page
from app.admin.repository import ACCOUNT_WITHDRAWN, INSUFFICIENT_HEARTS, AdminRepository
from app.core.http import raise_for_status

# 목록 한 줄과 상세가 같이 쓰는 칸. 학교는 학교 메일 인증 전이면 null 이다(universities 임베드가 null).
_SUMMARY_SELECT = "id,nickname,status,created_at,gender,acquisition_channel,universities(name)"
_DETAIL_SELECT = ("id,nickname,status,created_at,gender,acquisition_channel,acquisition_note,last_active_at,auto_hidden_at,"
                  "school_email_verified_at,universities(name),profile_avatars(storage_path,status,created_at)")
# 합계에서 세는 값(DB enum gender · acquisition_channel). 고르기 전(null)은 "none" 으로 따로 센다.
GENDERS = ("male", "female")
CHANNELS = ("everytime", "instagram", "friend", "community", "other")
# 주문 번호 · 토큰 해시는 일부러 고르지 않는다(사용자 상세에는 싣지 않는다 — 결제 조회에서 번호로 찾는다).
_PURCHASE_SELECT = "id,store,product_id,status,is_test,heart_amount,bonus_hearts,clawed_back_hearts,purchased_at"
NOTE_ACTION = "profile_note"
_LIKE_SPECIAL = re.compile(r"([\\%_])")
# 목록 정렬(머리 칸 누르기, 사용자 요청 11-22): 응답 칸 이름 → PostgREST order 칸. 학교는 to-one 임베드 정렬(PostgREST v11+).
# 받은 신고(report_count)는 reports 표에서 따로 세는 값이라 PostgREST 로 정렬할 수 없다 — 허용 목록에 없다(422).
# status · gender · acquisition_channel 은 DB enum 이라 글자 순이 아니라 enum 선언 순으로 정렬된다.
USER_SORTS = {
    "created_at": "created_at", "nickname": "nickname", "id": "id", "university": "universities(name)", "status": "status",
    "gender": "gender", "acquisition_channel": "acquisition_channel",
}
# null 이 되는 칸(입력 전 · 학교 인증 전)은 오름 · 내림 모두 맨 뒤로 — 값 있는 줄을 먼저 본다.
_NULLABLE_SORTS = {"nickname", "university", "gender", "acquisition_channel"}


def _escape_like(text: str) -> str:
    return _LIKE_SPECIAL.sub(lambda match: "\\" + match[1], text)


def user_order(sort: str, direction: str) -> str:
    """정렬 칸 + 방향 → PostgREST order. 끝에 id 로 동점을 깬다(쪽 사이에 줄이 겹치거나 빠지지 않게)."""
    if sort == "id":
        return f"id.{direction}"
    nulls = ".nullslast" if sort in _NULLABLE_SORTS else ""
    return f"{USER_SORTS[sort]}.{direction}{nulls},id.{direction}"


class AdminUserRepository(AdminRepository):

    async def admin_ids(self) -> list[str]:
        """관리자 명단 전체(몇 명뿐이다). 사용자 목록에서 빼는 데 쓴다."""
        return [row["user_id"] for row in await self._rows("admin_users", {"select": "user_id"})]

    async def list_users(
        self, *, nickname: str | None, profile_id: str | None, page: Page, exclude_ids: list[str],
        order: str = "created_at.desc,id.desc",
    ) -> tuple[list[dict], int]:
        """한 쪽과 전체 건수(기본 가입 최근 순, order 는 [user_order]). nickname 은 부분 일치(대소문자 무시, LIKE 특수문자는 이스케이프),
        profile_id 는 일치. 관리자는 PostgREST 필터로 뺀다 — 건수와 쪽이 관리자 때문에 어긋나지 않게."""
        if profile_id in exclude_ids:
            return [], 0
        params = {"select": _SUMMARY_SELECT, "order": order}
        if profile_id:
            params["id"] = f"eq.{profile_id}"
        elif exclude_ids:
            params["id"] = f"not.in.({','.join(exclude_ids)})"
        if nickname:
            params["nickname"] = f"ilike.*{_escape_like(nickname)}*"
        return await self.read_page("profiles", params, page)

    async def e2e_university_ids(self) -> list[str]:
        """시험 학교(`universities.region_group = 'e2e'`, 사용자 결정 2026-11-12) id 전부(몇 곳뿐이다)."""
        return [row["id"] for row in await self._rows("universities", {"select": "id", "region_group": "eq.e2e"})]

    async def count_profiles_by(self, column: str, values: tuple[str, ...], exclude_ids: list[str],
                                exclude_university_ids: list[str]) -> dict[str, int]:
        """값마다 인원 + null 인원("none"). 관리자와 시험 학교 사람은 빼고, 상태(가입 중 등)는 가리지 않는다.
        학교 없는 사람(학교 메일 인증 전)은 센다 — `universities!inner` 는 그 사람까지 빼므로 학교 id 로 거른다.
        값마다 count=exact 한 번(묶어 세는 집계는 PostgREST 기본 설정에서 꺼져 있고, 줄을 받아 세면 1000줄 상한에 잘린다)."""
        base = {"select": "id"}
        if exclude_ids:
            base["id"] = f"not.in.({','.join(exclude_ids)})"
        if exclude_university_ids:  # 빈 not.in.() 은 PostgREST 가 거절한다 — 시험 학교가 없으면 거르지 않는다
            base["or"] = f"(university_id.is.null,university_id.not.in.({','.join(exclude_university_ids)}))"
        keys = (*values, "none")
        counts = await asyncio.gather(*(
            self._count("profiles", {**base, column: "is.null" if key == "none" else f"eq.{key}"}) for key in keys))
        return dict(zip(keys, counts))

    async def count_reports_by_target(self, profile_ids: list[str]) -> dict[str, int]:
        """목록 줄마다 받은 신고 수 — 한 번에 묶어 센다.
        shortcut: PostgREST 응답 상한(기본 1000줄)을 넘으면 세던 값이 잘린다 — 목록 50명에 신고가 1000건 넘을 일이 없다, 넘으면 count 함수로."""
        if not profile_ids:
            return {}
        rows = await self._rows("reports", {
            "select": "target_profile_id", "target_profile_id": f"in.({','.join(profile_ids)})",
        })
        counts: dict[str, int] = {}
        for row in rows:
            counts[row["target_profile_id"]] = counts.get(row["target_profile_id"], 0) + 1
        return counts

    async def find_profile_by_school_email(self, hmac_literal: str) -> str | None:
        """학교 메일 해시(`\\x…`)가 정확히 일치하는 계정. 메일 원문은 여기까지 오지 않는다."""
        rows = await self._rows("school_email_claims", {
            "select": "profile_id", "school_email_hmac": f"eq.{hmac_literal}",
        })
        return rows[0]["profile_id"] if rows else None

    async def fetch_user_profile(self, profile_id: UUID | str) -> dict | None:
        rows = await self._rows("profiles", {"select": _DETAIL_SELECT, "id": f"eq.{profile_id}"})
        return rows[0] if rows else None

    async def fetch_profile_status(self, profile_id: UUID | str) -> str | None:
        rows = await self._rows("profiles", {"select": "status", "id": f"eq.{profile_id}"})
        return rows[0]["status"] if rows else None

    async def count_reports(self, profile_id: UUID | str) -> int:
        return await self._count("reports", {"select": "id", "target_profile_id": f"eq.{profile_id}"})

    async def count_contact_blocks(self, profile_id: UUID | str) -> int:
        return await self._count("contact_blocks", {"select": "owner_id", "owner_id": f"eq.{profile_id}"})

    async def fetch_heart_balance(self, profile_id: UUID | str) -> int:
        rows = await self._rows("entitlements", {"select": "heart_balance", "profile_id": f"eq.{profile_id}"})
        return rows[0]["heart_balance"] if rows else 0

    async def list_heart_ledger(self, profile_id: UUID | str, limit: int) -> list[dict]:
        return await self._rows("heart_transactions", {
            "select": "id,created_at,amount,reason", "profile_id": f"eq.{profile_id}",
            "order": "created_at.desc,id.desc", "limit": str(limit),
        })

    async def list_purchases(self, profile_id: UUID | str, limit: int) -> list[dict]:
        return await self._rows("purchases", {
            "select": _PURCHASE_SELECT, "profile_id": f"eq.{profile_id}", "order": "purchased_at.desc", "limit": str(limit),
        })

    async def list_notes(self, profile_id: UUID | str, limit: int) -> list[dict]:
        """메모 = 작업 기록 admin_actions 의 profile_note 줄(글자는 reason 칸). 최근 순."""
        return await self._rows("admin_actions", {
            "select": "id,created_at,admin_user_id,reason", "action": f"eq.{NOTE_ACTION}", "target_type": "eq.profile",
            "target_id": f"eq.{profile_id}", "order": "created_at.desc,id.desc", "limit": str(limit),
        })

    async def adjust_hearts(self, admin_user_id: UUID, profile_id: UUID, amount: int, reason: str, ip: str | None) -> dict:
        """하트 조정과 작업 기록을 DB 함수 하나로. 잔액이 모자라면 409 insufficient_hearts, 탈퇴 계정은 409 account_withdrawn."""
        return await self._rpc("admin_adjust_hearts", {
            "p_admin": str(admin_user_id), "p_profile": str(profile_id), "p_amount": amount, "p_reason": reason, "p_ip": ip,
        }, conflicts={"insufficient hearts": INSUFFICIENT_HEARTS, "profile withdrawn": ACCOUNT_WITHDRAWN})

    async def read_private_contact(self, profile_id: UUID | str) -> dict:
        """복호화한 전화번호 · 카카오톡 아이디(저장소를 encryption_key 와 함께 만들었을 때만). 값이 없으면 None.
        열람 경로 하나만 부른다 — 부르기 전에 작업 기록을 먼저 남긴다. 키는 JSON 본문으로만 보낸다."""
        response = await self._post("rpc/decrypt_phone_number", json={
            "p_profile_id": str(profile_id), "p_key": self._encryption_key,
        })
        raise_for_status(response)
        phone = response.json() if response.content else None
        return {"phone_number": phone, "kakao_id": (await self._read_private(profile_id, ("kakao_id",)))["kakao_id"]}

    async def close_account(
        self, admin_user_id: UUID, profile_id: UUID, email_hmac: str | None, key_version: int, reason: str,
        verified_by: str, ip: str | None,
    ) -> dict:
        """탈퇴(기존 withdraw_account 재사용)와 작업 기록을 DB 함수 하나로. email_hmac 은 PostgREST bytea 리터럴 그대로, 없으면 None.
        이미 탈퇴했으면 409 account_withdrawn."""
        return await self._rpc("admin_close_account", {
            "p_admin": str(admin_user_id), "p_profile": str(profile_id), "p_email_hmac": email_hmac,
            "p_key_version": key_version, "p_reason": reason, "p_verified_by": verified_by, "p_ip": ip,
        }, conflicts={"profile withdrawn": ACCOUNT_WITHDRAWN})
