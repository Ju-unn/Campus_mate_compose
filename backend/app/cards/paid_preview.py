"""결제 전 유료 카드의 흐린 사진(보안 점검 #3, 2026-10-12 사용자 결정 (a) "서버가 흐린 이미지를 따로 만든다").

아바타 원본은 공개 저장소에 있고 주소에 상대 profile_id 가 들어 있다 — 주소를 내려보내면 응답을 가로채 결제 없이
얼굴을 본다. 그래서 결제 전에는 주소를 싣지 않고, 서버가 원본을 받아 8×10 칸으로 줄인 JPEG 만 base64 로 싣는다.
80칸에는 얼굴을 알아볼 정보도, 원본 해상도로 되돌릴 정보도 없다. 앱은 이것을 키워 blur 10 으로 그린다(pen `qoYnh`).

받아들인 남은 위험: 같은 원본이면 늘 같은 미리보기가 나온다(결정적 출력). 그래서 여러 계정을 가진 사람이 무료
카드로 이미 본 사람들의 원본(공개 주소)에 이 함수를 똑같이 돌려 두고, 결제 전 미리보기와 대조해 누구인지 맞힐 수
있다. 원본을 되살리는 것이 아니라 "이미 아는 얼굴 중 누구인가" 를 고르는 공격이고, 무료 카드로 그 사람을 먼저 받아야
한다. 막으려면 요청마다 잡음을 섞어야 하는데 그러면 캐시를 못 쓰고 화면이 열 때마다 바뀐다 — 그래서 두지 않았다
(검토 지적, 2026-10-12)."""
import asyncio
import base64
import io
import logging
from collections import OrderedDict

from PIL import Image, ImageFilter, ImageOps

logger = logging.getLogger(__name__)

# 가로×세로 칸 수. 원본 가운데를 4:5 로 잘라 줄인다. 화면은 88×88 원에 BoxFit.cover 로 그려서 실제로 보이는 것은
# 가운데 8×8 칸뿐이다(위아래 한 줄씩은 잘린다).
PREVIEW_SIZE = (8, 10)
_BLUR_RADIUS = 1
_JPEG_QUALITY = 50
# (경로, 크기, 강도) → base64 미리보기. 같은 아바타면 다시 받지 않는다. 유료 카드 한 칸은 수백 바이트, 홈 레일
# 한 칸(112×140)은 2~3KB 라 256칸이 다 홈 것이어도 1MB 안팎이다.
# ponytail: 프로세스마다 따로인 메모리 캐시다 — 인스턴스가 늘면 인스턴스마다 한 번씩 받는다. 그게 부담이 되면 공용 캐시로.
_CACHE_SIZE = 256
_cache: OrderedDict[tuple[str, tuple[int, int], float], str] = OrderedDict()


def blur_preview(original: bytes, size: tuple[int, int] = PREVIEW_SIZE, radius: float = _BLUR_RADIUS) -> bytes:
    """원본 그림 → size 크기 JPEG. 가운데를 size 비율로 잘라 칸마다 평균을 낸 뒤(BOX) 반경 radius 픽셀로 한 번 더
    섞는다. 기본값이 유료 카드(8×10, 1)다. 홈 레일(home/router)은 크기 · 강도만 바꿔 쓴다."""
    with Image.open(io.BytesIO(original)) as image:
        small = ImageOps.fit(image.convert("RGB"), size, Image.Resampling.BOX)
    out = io.BytesIO()
    small.filter(ImageFilter.GaussianBlur(radius)).save(out, "JPEG", quality=_JPEG_QUALITY, optimize=True)
    return out.getvalue()


async def cached_preview(storage, path: str, size: tuple[int, int] = PREVIEW_SIZE,
                         radius: float = _BLUR_RADIUS) -> str:
    """아바타 경로 → base64 흐린 JPEG. 같은 (경로 · 크기 · 강도)면 다시 받지 않는다 — 유료 카드와 홈 레일이 같은
    아바타를 다른 크기로 만들어도 서로 덮지 않는다. 받기 · 읽기 실패는 그대로 올린다(캐시하지 않아 다음 요청이 다시 해 본다)."""
    key = (path, size, radius)
    if key in _cache:
        _cache.move_to_end(key)
        return _cache[key]
    original = await storage.download(path)
    # 디코딩 · 축소는 CPU 일이다 — 이벤트 루프 위에서 돌면 그동안 다른 요청이 멈춘다.
    preview = base64.b64encode(await asyncio.to_thread(blur_preview, original, size, radius)).decode("ascii")
    _cache[key] = preview
    if len(_cache) > _CACHE_SIZE:
        _cache.popitem(last=False)
    return preview


async def preview_of(storage, path: str | None) -> str | None:
    """유료 카드 미리보기. 아바타가 없거나 받기 · 읽기에 실패하면 None(앱은 회색 원, 카드는 그대로 열린다)."""
    if path is None:
        return None
    try:
        return await cached_preview(storage, path)
    except Exception as error:
        # 예외 문구에는 저장소 주소(경로 = profile_id)가 들어 있어 종류 이름만 남긴다(COMMON §3).
        logger.warning("유료 카드 미리보기를 만들지 못했다 — 회색 원으로 둔다 (%s)", type(error).__name__)
        return None


def clear_cache() -> None:
    """시험이 서로 섞이지 않게 비운다."""
    _cache.clear()
