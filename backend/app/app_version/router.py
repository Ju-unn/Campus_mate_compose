import logging
import re

from fastapi import APIRouter, Depends, Response

from app.core.deps import get_settings
from app.settings import Settings

logger = logging.getLogger(__name__)

router = APIRouter()

# 숫자.숫자.숫자 만. `\d` 는 아랍 숫자 같은 다른 문자 숫자도 받아서 [0-9] 로 쓴다.
_VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+")
# 앱은 시작할 때와 앱으로 돌아올 때 묻는다. 값을 바꾸는 건 새 리비전(배포)이라 5분 늦게 보여도 괜찮다.
_CACHE_CONTROL = "public, max-age=300"


def _minimum_version(settings: Settings) -> str | None:
    """env `MIN_APP_VERSION`. 비었거나 형식이 틀리면 None — 아무도 막지 않는다. 틀린 값으로 Settings() 가 죽으면 서버 전체가
    멈추고, 틀린 값을 그대로 내려 주면 앱이 비교를 못 한다. 틀리게 적은 걸 알아챌 수 있게 경고만 남긴다."""
    value = settings.min_app_version.strip()
    if not value:
        return None
    if not _VERSION.fullmatch(value):
        logger.warning("MIN_APP_VERSION 형식이 올바르지 않아 무시한다(숫자.숫자.숫자 여야 한다)")
        return None
    return value


@router.get("/app/version")
def get_app_version(response: Response, settings: Settings = Depends(get_settings)) -> dict:
    """인증 없는 공개 경로 — 로그인 전 시작 화면에서도 앱이 묻는다. 이 값 **미만** 인 앱은 업데이트 안내로 막힌다.
    값은 버전 숫자뿐이라 숨길 것이 없다."""
    response.headers["Cache-Control"] = _CACHE_CONTROL
    return {"min_version": _minimum_version(settings)}
