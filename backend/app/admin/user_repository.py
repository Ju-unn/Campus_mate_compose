"""관리자 사용자 화면(설계 10-18 §8-3)의 DB 호출. 읽기는 PostgREST, 바꾸는 일은 DB 함수 하나(한 트랜잭션, 마이그레이션 20261018120000).

학교 메일은 원문을 받지 않는다 — 부르는 쪽이 해시(`\\x…` 리터럴)만 넘긴다."""
import re
from uuid import UUID

from app.admin.repository import ACCOUNT_WITHDRAWN, INSUFFICIENT_HEARTS, AdminRepository
from app.core.http import raise_for_status

# 목록 한 줄과 상세가 같이 쓰는 칸. 학교는 학교 메일 인증 전이면 null 이다(universities 임베드가 null).
_SUMMARY_SELECT = "id,nickname,status,created_at,universities(name)"
_DETAIL_SELECT = ("id,nickname,status,created_at,last_active_at,auto_hidden_at,school_email_verified_at,"
                  "universities(name),profile_avatars(storage_path,status,created_at)")
# 주문 번호 · 토큰 해시는 일부러 고르지 않는다(사용자 상세에는 싣지 않는다 — 결제 조회에서 번호로 찾는다).
_PURCHASE_SELECT = "id,store,product_id,status,is_test,heart_amount,bonus_hearts,clawed_back_hearts,purchased_at"
NOTE_ACTION = "profile_note"
_LIKE_SPECIAL = re.compile(r"([\\%_])")


class AdminUserRepository(AdminRepository):

    async def admin_ids(self) -> list[str]:
        """관리자 명단 전체(몇 명뿐이다). 사용자 목록에서 빼는 데 쓴다."""
        return [row["user_id"] for row in await self._rows("admin_users", {"select": "user_id"})]

    async def list_users(
        self, *, nickname: str | None, profile_id: str | None, limit: int, exclude_ids: list[str],
    ) -> list[dict]:
        """가입 최근 순. nickname 은 부분 일치(대소문자 무시, LIKE 특수문자는 이스케이프), profile_id 는 일치."""
        params = {"select": _SUMMARY_SELECT, "order": "created_at.desc", "limit": str(limit)}
        if profile_id:
            params["id"] = f"eq.{profile_id}"
        elif exclude_ids:
            params["id"] = f"not.in.({','.join(exclude_ids)})"
        if nickname:
            escaped = _LIKE_SPECIAL.sub(lambda match: "\\" + match[1], nickname)
            params["nickname"] = f"ilike.*{escaped}*"
        rows = await self._rows("profiles", params)
        return [row for row in rows if row["id"] not in exclude_ids]

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

    async def _count(self, path: str, params: dict) -> int:
        """전체 건수 — Content-Range 의 `/` 뒤(`AccountRepository.count_contact_blocks_not_on` 와 같은 방식)."""
        response = await self._client.get(
            f"{self._postgrest_url}/{path}", params={**params, "limit": "1"}, headers=self._with_prefer("count=exact"),
        )
        raise_for_status(response)
        return int(response.headers["content-range"].rsplit("/", 1)[1])

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
