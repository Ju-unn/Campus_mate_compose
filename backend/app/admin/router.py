"""관리자 웹 대시보드 API(설계 10-18 §8). 모든 경로는 get_admin_caller 를 거친다(tests/admin/test_admin_caller.py 가 센다)."""
from fastapi import APIRouter, Depends

from app.admin.caller import AdminCaller, get_admin_caller

router = APIRouter(prefix="/admin")


@router.get("/me")
async def get_admin_me(caller: AdminCaller = Depends(get_admin_caller)) -> dict:
    """로그인 직후 화면 분기용. 관문을 통과했다는 것 자체가 답이라 aal · is_admin 은 늘 같은 값이다 —
    막히면 401 / 403(mfa_required · not_admin)으로 온다."""
    return {"user_id": str(caller.admin_user_id), "aal": "aal2", "is_admin": True}
