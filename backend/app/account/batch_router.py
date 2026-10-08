import logging
from datetime import datetime, timedelta, timezone

import httpx
from fastapi import APIRouter, Depends, Header

from app.account.repository import AccountRepository, SupabaseAdmin
from app.core.batch_auth import verify_oidc_token
from app.core.deps import get_client, get_now, get_settings
from app.heart_tasks.cleanup import purge_reviewed_proofs
from app.heart_tasks.repository import HeartTaskRepository
from app.heart_tasks.storage import HeartProofStorage
from app.settings import Settings
from app.signup_policy import IDENTITY_KEY_VERSION

logger = logging.getLogger(__name__)

router = APIRouter()

# 보관 기간(계획서 B3). 재가입 제한 2개월은 여기가 아니라 SQL `withdraw_account` 안에 있다
# (20260927030100 — 정지 중 탈퇴는 무기한). 이 배치는 만료된 제한 행을 지울 뿐이다.
WITHDRAWN_RETENTION = timedelta(days=30)
# 소셜로 가입하고 학교 메일 확인을 이만큼 안 한 계정은 지운다(소셜 로그인 전환).
UNVERIFIED_RETENTION_DAYS = 14
REPORT_RETENTION = timedelta(days=365)
# 학교 메일 verify 가 지우지 못한 임시 이메일 계정(provider=email 하나뿐, 프로필 없음)은 이만큼 뒤 지운다.
TEMP_EMAIL_ACCOUNT_RETENTION = timedelta(hours=24)
ADMIN_USERS_PER_PAGE = 100
# ponytail: 한 번에 100명. 남은 사람은 다음 날 이어서 지운다 — 하루 탈퇴가 이보다 많아지면 올리거나 여러 번 돈다.
CLEANUP_ACCOUNT_LIMIT = 100
# 사람마다 `{profile_id}/` 폴더가 있는 버킷 전부.
STORAGE_BUCKETS = ("avatars", "profile-photos", "student-id-temp", "heart-task-proofs")


async def _delete_accounts(admin: SupabaseAdmin, profile_ids: list[str], label: str,
                           still_due=None) -> tuple[int, int]:
    """버킷 넷(STORAGE_BUCKETS)의 파일 → auth 사용자(profiles 는 cascade). (지운 수, 건너뛴 수).

    still_due 를 주면 사람마다 지우기 **직전에** 다시 묻는다 — False 이거나 묻다 실패하면 건너뛴다."""
    deleted = skipped = 0
    for profile_id in profile_ids:
        try:
            if still_due is not None and not await still_due(profile_id):
                logger.warning("%s 정리 건너뜀(재확인) profile=%s", label, profile_id)
                skipped += 1
                continue
            for bucket in STORAGE_BUCKETS:
                await admin.empty_folder(bucket, profile_id)
            # 파일이 하나라도 남으면 여기까지 오지 않는다 — auth 행이 사라진 뒤에는 그 파일을 찾을 길이 없다.
            await admin.delete_user(profile_id)
        except Exception:
            # 한 사람 때문에 뒷사람과 뒤 단계가 멈추지 않게 한다. 내일 다시 고른다.
            logger.warning("%s 정리 건너뜀 profile=%s", label, profile_id)
            skipped += 1
            continue
        deleted += 1
    return deleted, skipped


async def run_cleanup(accounts: AccountRepository, admin: SupabaseAdmin, now: datetime) -> dict:
    """매일 04:00(Asia/Seoul). 다섯 가지를 하고 전부 멱등이다 — 다시 돌리면 0건이다.

    ① 탈퇴 30일 지난 계정: 버킷 넷(STORAGE_BUCKETS)의 파일 → auth 사용자(profiles 는 cascade)
    ①-b 가입 14일이 지나도록 학교 메일 확인을 안 한 계정: ① 과 같은 길, 지우기 직전 재확인(deleted_unverified)
    ①-c 학교 메일 verify 가 못 지운 임시 이메일 계정 24시간 뒤(deleted_temp_email_accounts)
    ② 처리 끝나고 1년 지난 신고(열린 신고는 남는다) ③ 만료된 재가입 제한 ④ 옛 키 버전 지인 차단 세기(경고)
    ⑤ 검수 끝나고 60일 지난 하트 인증샷은 엔드포인트(run_cleanup_batch)가 이어서 지운다.
    skipped_accounts 는 ① · ①-b 에서 건너뛴 사람을 합친 수다."""
    withdrawn = await accounts.fetch_withdrawn_before(now - WITHDRAWN_RETENTION, CLEANUP_ACCOUNT_LIMIT)
    deleted, skipped = await _delete_accounts(admin, withdrawn, "탈퇴 계정")
    unverified = (await accounts.list_unverified_accounts(UNVERIFIED_RETENTION_DAYS, CLEANUP_ACCOUNT_LIMIT)
                  )[:CLEANUP_ACCOUNT_LIMIT]
    deleted_unverified, skipped_unverified = await _delete_accounts(
        admin, unverified, "학교 메일 미확인 계정", still_due=accounts.is_still_unverified)
    try:
        deleted_temp = await _delete_temp_email_accounts(accounts, admin, now)
    except Exception as exc:
        # 이 단계가 실패해도 나머지 정리는 계속한다. 내일 다시 한다.
        logger.warning("임시 이메일 계정 정리 실패 %s", type(exc).__name__)
        deleted_temp = 0

    stale = await accounts.count_contact_blocks_not_on(IDENTITY_KEY_VERSION)
    if stale:
        # 키를 바꾼 뒤 옛 버전 행은 후보 대조에서 빠진다(같은 버전끼리만 맞춘다).
        logger.warning("contact_blocks stale key_version rows=%d (current=%d)", stale, IDENTITY_KEY_VERSION)
    return {
        "deleted_accounts": deleted,
        "skipped_accounts": skipped + skipped_unverified,
        "deleted_unverified": deleted_unverified,
        "deleted_temp_email_accounts": deleted_temp,
        "deleted_reports": await accounts.delete_reports_before(now - REPORT_RETENTION),
        "deleted_signup_blocks": await accounts.delete_signup_blocks_before(now),
        "stale_key_rows": stale,
    }


def _is_temp_email_account(user: dict, cutoff: datetime) -> bool:
    """provider 가 email 하나뿐이고 cutoff 전에 만들어진 auth 사용자. 프로필 유무는 지우기 직전에 따로 본다."""
    providers = [identity.get("provider") for identity in user.get("identities") or []]
    if providers != ["email"]:
        return False
    try:
        created = datetime.fromisoformat(user["created_at"])
    except (KeyError, TypeError, ValueError):
        return False  # 언제 만들었는지 모르면 지우지 않는다
    if created.tzinfo is None:
        created = created.replace(tzinfo=timezone.utc)
    return created < cutoff


async def _delete_temp_email_accounts(accounts: AccountRepository, admin: SupabaseAdmin, now: datetime) -> int:
    """임시 이메일 계정 잔여물을 최대 CLEANUP_ACCOUNT_LIMIT 개 지운다. 지우기 직전에 프로필이 없는지 다시 읽고,
    있거나 못 읽으면 건너뛴다(소셜 전환 전 학교 메일 OTP 로 가입한 옛 계정은 프로필이 있다). 파일은 없다."""
    # ponytail: 관리자 목록 전체 스캔, 가입자가 많아지면 DB 함수로 옮긴다
    cutoff = now - TEMP_EMAIL_ACCOUNT_RETENTION
    candidates: list[str] = []
    page = 1
    while len(candidates) < CLEANUP_ACCOUNT_LIMIT:
        users = await admin.list_users(page, ADMIN_USERS_PER_PAGE)
        candidates += [u["id"] for u in users if _is_temp_email_account(u, cutoff)]
        if len(users) < ADMIN_USERS_PER_PAGE:
            break
        page += 1

    deleted = 0
    for user_id in candidates[:CLEANUP_ACCOUNT_LIMIT]:
        try:
            if await accounts.has_profile(user_id):
                continue
            await admin.delete_user(user_id)
        except Exception:
            logger.warning("임시 이메일 계정 정리 건너뜀 user=%s", user_id)
            continue
        deleted += 1
    return deleted


@router.post("/batch/cleanup")
async def run_cleanup_batch(
    authorization: str | None = Header(default=None),
    settings: Settings = Depends(get_settings),
    client: httpx.AsyncClient = Depends(get_client),
    now: datetime = Depends(get_now),
) -> dict:
    """Cloud Scheduler 전용. 카드 · 채팅 배치와 같은 문(스케줄러 ID 토큰)을 쓴다."""
    await verify_oidc_token(
        authorization,
        audience=settings.batch_audience,
        service_account_email=settings.batch_service_account,
    )

    key = settings.supabase_service_role_key
    result = await run_cleanup(
        AccountRepository(settings.postgrest_url, key, client), SupabaseAdmin(settings, client), now
    )
    # ⑤ 검수 끝나고 60일 지난 무료 하트 인증샷(heart_tasks/cleanup.py).
    result["deleted_heart_proofs"] = await purge_reviewed_proofs(
        HeartTaskRepository(settings.postgrest_url, key, client),
        HeartProofStorage(settings.storage_url, key, client), now,
    )
    return result
