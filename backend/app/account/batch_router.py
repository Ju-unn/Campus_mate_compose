import logging
from datetime import datetime, timedelta

import httpx
from fastapi import APIRouter, Depends, Header

from app.account.repository import AccountRepository, SupabaseAdmin
from app.core.batch_auth import verify_batch_caller
from app.core.deps import get_client, get_now, get_settings
from app.settings import Settings
from app.signup_policy import IDENTITY_KEY_VERSION

logger = logging.getLogger(__name__)

router = APIRouter()

# 보관 기간(계획서 B3). 재가입 제한 2개월은 여기가 아니라 SQL `withdraw_account` 안에 있다
# (20260927030100 — 정지 중 탈퇴는 무기한). 이 배치는 만료된 제한 행을 지울 뿐이다.
WITHDRAWN_RETENTION = timedelta(days=30)
REPORT_RETENTION = timedelta(days=365)
# ponytail: 한 번에 100명. 남은 사람은 다음 날 이어서 지운다 — 하루 탈퇴가 이보다 많아지면 올리거나 여러 번 돈다.
CLEANUP_ACCOUNT_LIMIT = 100
# 사람마다 `{profile_id}/` 폴더가 있는 버킷 전부.
STORAGE_BUCKETS = ("avatars", "profile-photos", "student-id-temp")


async def run_cleanup(accounts: AccountRepository, admin: SupabaseAdmin, now: datetime) -> dict:
    """매일 04:00(Asia/Seoul). 네 가지를 하고 전부 멱등이다 — 다시 돌리면 0건이다.

    ① 탈퇴 30일 지난 계정: 버킷 셋의 파일 → auth 사용자(profiles 는 cascade)
    ② 1년 지난 신고 ③ 만료된 재가입 제한 ④ 옛 키 버전 지인 차단 세기(경고)"""
    deleted = skipped = 0
    for profile_id in await accounts.fetch_withdrawn_before(now - WITHDRAWN_RETENTION, CLEANUP_ACCOUNT_LIMIT):
        try:
            for bucket in STORAGE_BUCKETS:
                await admin.empty_folder(bucket, profile_id)
            # 파일이 하나라도 남으면 여기까지 오지 않는다 — auth 행이 사라진 뒤에는 그 파일을 찾을 길이 없다.
            await admin.delete_user(profile_id)
        except Exception:
            # 한 사람 때문에 뒷사람과 ②~④ 가 멈추지 않게 한다. 내일 다시 고른다.
            logger.warning("탈퇴 계정 정리 건너뜀 profile=%s", profile_id)
            skipped += 1
            continue
        deleted += 1

    stale = await accounts.count_contact_blocks_not_on(IDENTITY_KEY_VERSION)
    if stale:
        # 키를 바꾼 뒤 옛 버전 행은 후보 대조에서 빠진다(같은 버전끼리만 맞춘다).
        logger.warning("contact_blocks stale key_version rows=%d (current=%d)", stale, IDENTITY_KEY_VERSION)
    return {
        "deleted_accounts": deleted,
        "skipped_accounts": skipped,
        "deleted_reports": await accounts.delete_reports_before(now - REPORT_RETENTION),
        "deleted_signup_blocks": await accounts.delete_signup_blocks_before(now),
        "stale_key_rows": stale,
    }


@router.post("/batch/cleanup")
async def run_cleanup_batch(
    x_batch_secret: str | None = Header(default=None),
    authorization: str | None = Header(default=None),
    settings: Settings = Depends(get_settings),
    client: httpx.AsyncClient = Depends(get_client),
    now: datetime = Depends(get_now),
) -> dict:
    """Cloud Scheduler 전용. 카드 · 채팅 배치와 같은 문(옛 공유 비밀 또는 스케줄러 ID 토큰)을 쓴다."""
    method = await verify_batch_caller(
        authorization=authorization, x_batch_secret=x_batch_secret,
        batch_secret=settings.card_batch_secret, audience=settings.batch_audience,
        service_account_email=settings.batch_service_account,
    )
    # 운영에 로깅 설정이 없어 INFO 는 안 보인다. 전환 확인용이고 5단계 PR 에서 이 줄째 지운다.
    logger.warning("batch %s auth=%s", "/batch/cleanup", method)

    key = settings.supabase_service_role_key
    return await run_cleanup(
        AccountRepository(settings.postgrest_url, key, client), SupabaseAdmin(settings, client), now
    )
