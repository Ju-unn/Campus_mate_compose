"""관리자 웹 대시보드 API(설계 10-18 §8). 모든 경로는 get_admin_caller 를 거친다(tests/admin/test_admin_caller.py 가 센다)."""
from fastapi import APIRouter, Depends

from app.admin.action_log import router as action_log_router
from app.admin.billing import router as billing_router
from app.admin.caller import AdminCaller, get_admin_caller
from app.admin.heart_task_review import router as heart_task_review_router
from app.admin.moderation import router as moderation_router
from app.admin.report_review import router as report_review_router
from app.admin.stats import router as stats_router
from app.admin.user_actions import router as user_actions_router
from app.admin.users import router as users_router

router = APIRouter(prefix="/admin")
# 조각별 하위 라우터는 여기서 붙인다 — main.py(공유 파일)는 /admin 하나만 안다.
router.include_router(heart_task_review_router)
router.include_router(report_review_router)
router.include_router(moderation_router)
router.include_router(users_router)
router.include_router(user_actions_router)
router.include_router(billing_router)
router.include_router(action_log_router)
router.include_router(stats_router)


@router.get("/me")
async def get_admin_me(caller: AdminCaller = Depends(get_admin_caller)) -> dict:
    """로그인 직후 화면 분기용. 관문을 통과했다는 것 자체가 답이라 aal · is_admin 은 늘 같은 값이다 —
    막히면 401 / 403(mfa_required · not_admin)으로 온다."""
    return {"user_id": str(caller.admin_user_id), "aal": "aal2", "is_admin": True}
