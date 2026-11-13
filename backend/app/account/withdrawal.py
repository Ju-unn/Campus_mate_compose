"""탈퇴의 두 길(앱 안 POST /account/withdraw · 관리자 대행 POST /admin/users/{id}/close-account)이 같이 쓰는 단계.

두 길이 각자 들고 있다가 갈라졌다(최종 점검 11-13 ③ — 대행은 졸업생 학번 해시 · 심사 중 졸업증명 사진을 빼먹었다).
재가입 제한 해시와 본인 토큰이 필요 없는 정리는 여기 하나만 둔다. 본인 토큰이 있어야 하는 정리(카카오 토큰 끊기 · 애플 철회 ·
로그아웃)와 관리자 키로 하는 카카오 끊기는 각 길에 남는다.
"""
from collections.abc import Awaitable, Callable
from datetime import datetime
from uuid import UUID

import httpx

from app.account.repository import AccountRepository, SupabaseAdmin
from app.graduate_verification.repository import GraduateRequestRepository
from app.graduate_verification.retention import delete_photo
from app.graduate_verification.storage import GraduateCertStorage
from app.settings import Settings
from app.signup_policy import IDENTITY_KEY_VERSION

Step = tuple[str, Callable[[], Awaitable[object]]]


async def rejoin_hash(accounts: AccountRepository, profile_id: UUID | str) -> tuple[str | None, int]:
    """탈퇴 재가입 제한에 쓸 (해시, 키 버전). 학교 메일 인증 기록이 먼저고, 없으면 졸업생 학번 해시, 둘 다 없으면 (None, 현재 버전).
    읽기 실패는 예외로 올린다 — 부르는 쪽이 아무것도 바꾸기 전에 503 으로 멈춘다(null 로 탈퇴시키면 제한을 잃는다)."""
    claim = await accounts.fetch_school_email_claim(profile_id)
    if claim is not None:
        return claim["school_email_hmac"], claim["key_version"]
    graduate = await accounts.fetch_graduate_claim(profile_id)
    if graduate is not None:
        return graduate["student_hmac"], graduate["key_version"]
    return None, IDENTITY_KEY_VERSION


def data_cleanup_steps(settings: Settings, client: httpx.AsyncClient, profile_id: UUID | str,
                       now: datetime) -> tuple[Step, ...]:
    """탈퇴(DB 함수) 뒤의 데이터 정리 — (단계 이름, 부를 함수). 각 단계는 부르는 쪽이 best-effort 로 돈다(실패해도 다음 단계).
    남은 것은 30일 정리 배치가 auth 사용자째 지운다."""
    accounts = AccountRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    admin = SupabaseAdmin(settings, client)
    graduate_repo = GraduateRequestRepository(settings.postgrest_url, settings.supabase_service_role_key, client)

    async def close_graduate_request() -> None:
        # 심사 중이던 졸업생 신청을 닫고(평문 비움) 사진을 지운다. 대기가 없으면 아무 일도 하지 않는다.
        cancelled = await graduate_repo.cancel_pending(profile_id, "account_withdrawn", now)
        if cancelled is not None:
            storage = GraduateCertStorage(settings.storage_url, settings.supabase_service_role_key, client)
            await delete_photo(graduate_repo, storage, cancelled["id"], cancelled["photo_path"])

    return (
        ("push_tokens", lambda: accounts.delete_push_tokens(profile_id)),
        ("student_id_files", lambda: admin.empty_folder("student-id-temp", profile_id)),
        ("graduate_request", close_graduate_request),
        ("graduate_files", lambda: admin.empty_folder("graduate-cert-temp", profile_id)),
    )
