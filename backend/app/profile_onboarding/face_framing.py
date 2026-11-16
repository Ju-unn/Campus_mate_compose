"""아바타 원본 사진을 얼굴 기준 머리·어깨 구도로 자른다(설계 docs/superpowers/specs/2026-11-16-avatar-face-framing-design.md).

앱은 아바타를 어디서나 가운데 자르기(BoxFit.cover)로 보인다. 전신 사진으로 만든 아바타는 얼굴이 위쪽 끝에 작게
있어 원 · 자세히 보기에서 잘렸다(11-16 운영). 생성 전에 원본을 출력과 같은 2:3 으로, 얼굴이 늘 같은 높이 · 크기에
오게 잘라 넘기면 지시문 7절("원본 구도를 지켜라")대로 아바타도 그 구도가 된다.

어떤 실패든 원본 그대로 돌려준다 — 이 단계 때문에 아바타 생성이 실패하면 안 된다(실패 5회 보상과 섞이지 않게).
"""
import asyncio
import io
import logging
from collections.abc import Callable

from google.cloud import vision
from PIL import Image, ImageOps

from app.core.logs import show_info

_logger = logging.getLogger(__name__)
show_info(_logger)

# 얼굴 상자(Vision bounding_poly) 높이 ÷ 자른 높이, 얼굴 가운데가 위에서 몇 % 에 오는가. 앱의 가운데 자르기에서
# 보이는 세로 띠(자세히 보기 286×260 → 19.7~80.3%, 원 · 정사각 → 16.7~83.3%, 모자이크 4:5 → 8.3~91.7%)
# 안에 얼굴(32.5~57.5%)이 다 든다. 실험 2차(설계 5.1절)로 정한 값이다 — 바꾸면 설계 문서 5절도 고친다.
FACE_HEIGHT_RATIO = 0.25
FACE_CENTER_Y = 0.45
# 자른 상자 가로 ÷ 세로 — 생성 크기 1024x1536(avatars.py)과 같다.
ASPECT = 2 / 3
# 머리 위에 사진이 모자라면(머리가 사진 위 끝에 붙은 전신 사진) 위를 이만큼까지 빈 칸으로 채워 얼굴을 내린다 — 비율은 자른 높이 대비.
MAX_TOP_PAD = 0.30
# 이보다 확신이 낮은 얼굴은 무시한다(무늬 · 포스터 오검출).
MIN_CONFIDENCE = 0.5
# 자른 높이가 이보다 작으면(아주 작은 얼굴) 원본을 그대로 쓴다 — 1차 시험에서 본 가장 작은 입력이 160×240 이다(설계 4.1절 ⑤).
MIN_CROP_HEIGHT = 240
# 워커는 큐에서 240초에 끊긴다 — 얼굴 찾기가 생성 시간을 빼앗지 않게 짧게 묶는다.
_VISION_TIMEOUT_SECONDS = 10
_JPEG_QUALITY = 95

Box = tuple[int, int, int, int]  # left, top, right, bottom (화소)


def crop_box(image_size: tuple[int, int], face: Box) -> Box | None:
    """얼굴 상자로 자를 2:3 상자를 정한다. 그림 전체와 같거나 MIN_CROP_HEIGHT 보다 작으면 None(원본 그대로).

    얼굴이 이미 큰 셀카는 더 넓게 볼 화소가 없으니 그림에 들어가는 가장 큰 2:3 상자를 쓴다.
    상자가 옆 · 아래로 나가면 크기는 그대로 두고 안으로 민다. 위로 나가면 MAX_TOP_PAD 까지는 그대로 두고
    (top 이 음수 — _crop 이 빈 칸을 채운다) 그보다 더 나가면 민다."""
    width, height = image_size
    left, top, right, bottom = face
    crop_height = min((bottom - top) / FACE_HEIGHT_RATIO, height, width / ASPECT)
    if crop_height < MIN_CROP_HEIGHT:
        return None
    crop_width = crop_height * ASPECT
    x = min(max((left + right) / 2 - crop_width / 2, 0), width - crop_width)
    # 그림 높이를 다 쓰는 상자(얼굴이 큰 셀카)는 채우지 않는다 — 아래를 잘라 위에 빈 띠를 붙일 뿐이다.
    lowest_top = -MAX_TOP_PAD * crop_height if crop_height < height else 0
    y = min(max((top + bottom) / 2 - FACE_CENTER_Y * crop_height, lowest_top), height - crop_height)
    box = (round(x), round(y), round(x + crop_width), round(y + crop_height))
    return None if box == (0, 0, width, height) else box


async def frame_on_face(make_client: Callable[[], vision.ImageAnnotatorAsyncClient], photo: bytes) -> bytes:
    """원본 바이트 → 얼굴 기준으로 자른 JPEG 바이트. 얼굴이 없거나 무엇이든 실패하면 원본 바이트 그대로.

    클라이언트를 "만드는 함수"로 받는다 — 인증 실패(GoogleAuthError)도 여기 try 안에서 잡혀 원본으로 넘어가야 한다."""
    try:
        image = await asyncio.to_thread(_upright_rgb, photo)
        # 회전을 반영한 그림을 Vision 에 보낸다 — Vision 좌표와 자를 그림의 방향이 반드시 같아야 한다.
        faces = await _faces(make_client(), await asyncio.to_thread(_jpeg, image))
        largest = max(faces, key=lambda b: (b[2] - b[0]) * (b[3] - b[1]), default=None)
        box = crop_box(image.size, largest) if largest else None
        # 수와 참거짓만 남긴다(COMMON §3) — 이미지 · 경로 · 좌표는 남기지 않는다.
        _logger.info("아바타 구도 맞춤 faces=%d face_ratio=%.2f cropped=%s", len(faces),
                     (largest[3] - largest[1]) / image.height if largest else 0.0, box is not None)
        if box is None:
            return photo
        return await asyncio.to_thread(lambda: _jpeg(_crop(image, box)))
    except Exception as error:  # noqa: BLE001 — 어떤 실패든 원본으로 만든다(위 설명)
        _logger.warning("아바타 구도 맞춤 건너뜀 — 원본으로 만든다 error=%s", type(error).__name__)
        return photo


async def _faces(client: vision.ImageAnnotatorAsyncClient, jpeg: bytes) -> list[Box]:
    # timeout= 은 한 번 시도의 시간일 뿐 라이브러리 기본 재시도가 최대 600초까지 다시 부른다 — 전체를 wait_for 로 묶는다.
    response = await asyncio.wait_for(
        client.batch_annotate_images(
            requests=[{"image": vision.Image(content=jpeg), "features": [{"type_": vision.Feature.Type.FACE_DETECTION}]}],
            timeout=_VISION_TIMEOUT_SECONDS,
        ),
        _VISION_TIMEOUT_SECONDS,
    )
    result = response.responses[0]
    if result.error.message:
        raise RuntimeError(result.error.message)
    return [_box(face.bounding_poly) for face in result.face_annotations if face.detection_confidence >= MIN_CONFIDENCE]


def _box(poly) -> Box:
    # 그림 밖으로 걸친 꼭짓점은 좌표가 빠져 0 으로 온다 — 0 은 그림 가장자리라 min · max 로 그대로 쓴다.
    xs = [vertex.x for vertex in poly.vertices]
    ys = [vertex.y for vertex in poly.vertices]
    return min(xs), min(ys), max(xs), max(ys)


def _crop(image: Image.Image, box: Box) -> Image.Image:
    """box 를 잘라 낸다. 위가 그림 밖(top < 0)이면 그 칸을 사진 맨 위 띠의 평균 색으로 채운다 — 생성 모델이 배경으로 그려 넣는다."""
    left, top, right, bottom = box
    if top >= 0:
        return image.crop(box)
    inside = image.crop((left, 0, right, bottom))
    strip = inside.crop((0, 0, inside.width, max(1, inside.height // 20)))
    canvas = Image.new("RGB", (right - left, bottom - top), strip.resize((1, 1), Image.Resampling.BOX).getpixel((0, 0)))
    canvas.paste(inside, (0, -top))
    return canvas


def _upright_rgb(photo: bytes) -> Image.Image:
    with Image.open(io.BytesIO(photo)) as opened:
        return ImageOps.exif_transpose(opened).convert("RGB")


def _jpeg(image: Image.Image) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, "JPEG", quality=_JPEG_QUALITY)
    return buffer.getvalue()
