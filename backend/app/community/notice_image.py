"""공지 그림 한 장의 검사 + 다시 저장하기(할 일 21, 보안 기준 21-3). 관리자가 올린 바이트를 그대로 내보내지 않는다.

순서: 10MB 상한 → 매직 바이트(jpeg · png · webp 만) → Pillow 로 열어 형식이 머리와 같은지 · 화소 수 상한 → 회전 반영 →
투명이면 흰 바탕 → RGB → 긴 변 1600 → JPEG(품질 80)로 다시 저장. 다시 저장한 바이트에는 EXIF(위치 포함) · ICC 가 없다.
"""
import io

from PIL import Image, ImageOps

from app.core.image_magic import sniff_image_type
from app.core.storage import public_object_url
from app.student_verification.image_validation import MAX_IMAGE_BYTES

# 공지 그림 공개 버킷(마이그레이션 20261124090000). 경로는 `{공지 id}.jpg` 하나뿐이다(DB polls_notice_image check).
NOTICE_BUCKET = "community-notices"
CONTENT_TYPE = "image/jpeg"

# 관리자 웹이 글자로 바꾸는 기계용 detail(설계 "그림 처리").
IMAGE_TYPE = "image_type"
IMAGE_TOO_LARGE = "image_too_large"
LONG_SIDE = 1600
JPEG_QUALITY = 80
# 풀기 전에 머리의 가로 × 세로로 막는다. 1600 으로 줄일 그림이라 이보다 큰 원본은 받을 까닭이 없다(Pillow 기본 상한의 반쯤).
# 전역 Image.MAX_IMAGE_PIXELS 는 다른 모듈(face_framing · paid_preview)도 쓰므로 건드리지 않는다.
MAX_PIXELS = 40_000_000
_PILLOW_FORMAT = {"image/jpeg": "JPEG", "image/png": "PNG"}

__all__ = ["CONTENT_TYPE", "IMAGE_TOO_LARGE", "IMAGE_TYPE", "LONG_SIDE", "MAX_IMAGE_BYTES", "NOTICE_BUCKET", "ImageRejected",
           "notice_image_path", "notice_image_url", "prepare_notice_image"]


def notice_image_path(notice_id) -> str:
    return f"{notice_id}.jpg"


def notice_image_url(supabase_url: str, image_path: str | None) -> str | None:
    """앱 · 관리자 웹이 받는 그림 주소 — 우리 버킷 경로로만 만든다(보안 기준 21-4)."""
    return None if image_path is None else public_object_url(supabase_url, NOTICE_BUCKET, image_path)


class ImageRejected(ValueError):
    def __init__(self, reason: str):
        super().__init__(reason)
        self.reason = reason


def _magic_format(data: bytes) -> str | None:
    """Pillow 형식 이름. JPEG · PNG 머리는 학생증과 같은 core/image_magic 판정, WEBP 는 공지만 받아 여기서 본다."""
    shared = _PILLOW_FORMAT.get(sniff_image_type(data))
    if shared is not None:
        return shared
    if len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "WEBP"
    return None


def _flatten(image: Image.Image) -> Image.Image:
    """투명한 곳은 흰 바탕으로. 팔레트 · 회색조 투명도 RGBA 로 바꿔 한 길로 합친다."""
    if image.mode in ("RGBA", "LA", "PA") or "transparency" in image.info:
        rgba = image.convert("RGBA")
        background = Image.new("RGB", rgba.size, (255, 255, 255))
        background.paste(rgba, mask=rgba.getchannel("A"))
        return background
    return image.convert("RGB")


def prepare_notice_image(data: bytes) -> bytes:
    """올릴 JPEG 바이트. 받을 수 없으면 ImageRejected(IMAGE_TYPE | IMAGE_TOO_LARGE)."""
    if len(data) > MAX_IMAGE_BYTES:
        raise ImageRejected(IMAGE_TOO_LARGE)
    expected = _magic_format(data)
    if expected is None:
        raise ImageRejected(IMAGE_TYPE)
    try:
        with Image.open(io.BytesIO(data), formats=[expected]) as opened:
            width, height = opened.size
            if opened.format != expected or width * height > MAX_PIXELS:
                raise ImageRejected(IMAGE_TYPE)
            image = _flatten(ImageOps.exif_transpose(opened))
    except ImageRejected:
        raise
    except (OSError, ValueError, SyntaxError, Image.DecompressionBombError):
        # 깨진 파일 · 잘린 파일 · Pillow 가 못 읽는 변형은 모두 "형식이 아니다" 로 본다.
        raise ImageRejected(IMAGE_TYPE) from None
    image.thumbnail((LONG_SIDE, LONG_SIDE))
    out = io.BytesIO()
    # exif · icc_profile 를 넘기지 않으므로 다시 저장한 파일에는 원본 메타데이터가 없다.
    image.save(out, format="JPEG", quality=JPEG_QUALITY)
    return out.getvalue()
