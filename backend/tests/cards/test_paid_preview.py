"""결제 전 유료 카드 사진(보안 점검 #3): 원본을 되살릴 수 없을 만큼 작게 줄인 JPEG 만 만든다."""
import io
import os

import pytest
from PIL import Image

from app.cards.paid_preview import PREVIEW_SIZE, blur_preview

# 1.5KB — base64 로 실어도 응답이 2KB 를 넘지 않는다.
MAX_PREVIEW_BYTES = 1500


def avatar_png(mode: str = "RGB", size: tuple[int, int] = (1024, 1536)) -> bytes:
    """gpt-image-1 아바타와 같은 1024×1536 PNG. 잡음이라 줄이기 전 정보가 가장 많다."""
    channels = len(mode)
    image = Image.frombytes(mode, size, os.urandom(size[0] * size[1] * channels))
    out = io.BytesIO()
    image.save(out, "PNG")
    return out.getvalue()


@pytest.mark.parametrize("mode", ["RGB", "RGBA"])
def test_the_preview_is_a_tiny_jpeg(mode):
    original = avatar_png(mode)

    preview = blur_preview(original)

    assert preview[:3] == b"\xff\xd8\xff"  # JPEG
    assert len(preview) <= MAX_PREVIEW_BYTES
    with Image.open(io.BytesIO(preview)) as image:
        # 80칸 — 얼굴을 알아볼 수 없고, 원본 해상도로 되돌릴 정보가 없다.
        assert image.size == PREVIEW_SIZE
        assert image.width * image.height <= 16 * 16


def test_a_square_fallback_avatar_also_fits():
    preview = blur_preview(avatar_png(size=(512, 512)))

    with Image.open(io.BytesIO(preview)) as image:
        assert image.size == PREVIEW_SIZE
