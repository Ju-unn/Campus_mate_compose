"""결제 전 유료 카드 사진(보안 점검 #3): 원본을 되살릴 수 없을 만큼 작게 줄인 JPEG 만 만든다."""
import base64
import io
import os

import pytest
from PIL import Image, ImageFilter, ImageOps

import app.cards.paid_preview as paid_preview
from app.cards.paid_preview import PREVIEW_SIZE, blur_preview, cached_preview, preview_of

# 1.5KB — base64 로 실어도 응답이 2KB 를 넘지 않는다.
MAX_PREVIEW_BYTES = 1500


def avatar_png(mode: str = "RGB", size: tuple[int, int] = (1024, 1536)) -> bytes:
    """아바타(gpt-image-2.5-flare)와 같은 1024×1536 PNG. 잡음이라 줄이기 전 정보가 가장 많다."""
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


def _paid_card_preview_before_generalizing(original: bytes) -> bytes:
    """크기 · 블러 강도를 인자로 받게 바꾸기 전의 blur_preview 를 글자 그대로 옮겼다(8×10 · BOX · blur 1 · 품질 50)."""
    with Image.open(io.BytesIO(original)) as image:
        small = ImageOps.fit(image.convert("RGB"), (8, 10), Image.Resampling.BOX)
    out = io.BytesIO()
    small.filter(ImageFilter.GaussianBlur(1)).save(out, "JPEG", quality=50, optimize=True)
    return out.getvalue()


def patterned_png(mode: str = "RGB") -> bytes:
    """늘 같은 무늬 그림(1024×1536). 잡음은 8×10 으로 줄이면 고른 회색이 돼 블러 강도가 바뀌어도 같은 바이트가 나온다 —
    회귀를 잡으려면 칸마다 색이 달라야 한다."""
    gradient = Image.linear_gradient("L").resize((1024, 1536))
    bands = [gradient, gradient.rotate(90), Image.radial_gradient("L").resize((1024, 1536))]
    image = Image.merge("RGB", bands)
    if mode == "RGBA":
        image.putalpha(gradient.rotate(180))
    out = io.BytesIO()
    image.save(out, "PNG")
    return out.getvalue()


@pytest.mark.parametrize("mode", ["RGB", "RGBA"])
def test_the_paid_card_preview_is_byte_for_byte_what_it_was(mode):
    """홈 레일이 같은 함수를 다른 크기 · 강도로 쓰게 됐어도 유료 카드 미리보기는 한 바이트도 바뀌지 않는다."""
    original = patterned_png(mode)

    assert blur_preview(original) == _paid_card_preview_before_generalizing(original)


def test_size_and_blur_strength_can_be_chosen():
    original = patterned_png()

    preview = blur_preview(original, size=(112, 140), radius=8)

    assert preview[:3] == b"\xff\xd8\xff"
    with Image.open(io.BytesIO(preview)) as image:
        assert image.size == (112, 140)
    assert blur_preview(original, size=(112, 140), radius=2) != preview


class _Storage:
    """원본을 늘 같은 그림으로 주는 가짜 Storage."""

    def __init__(self, original: bytes):
        self.original = original
        self.downloads = 0

    async def download(self, path: str) -> bytes:
        self.downloads += 1
        return self.original


@pytest.fixture
def fresh_cache():
    paid_preview.clear_cache()
    yield
    paid_preview.clear_cache()


async def test_the_paid_card_never_gets_the_rails_cached_picture(fresh_cache):
    """홈 레일(112×140, 반경 8)이 먼저 같은 아바타를 만들어도 유료 카드는 제 8×10 을 받는다. 캐시 키가 경로뿐이면
    유료 카드가 홈의 덜 흐린 큰 그림을 그대로 내려준다 — 결제 전에 얼굴이 더 보인다."""
    storage = _Storage(patterned_png())

    rail = await cached_preview(storage, "p/a.png", (112, 140), 8)
    paid = await preview_of(storage, "p/a.png")

    assert paid != rail
    with Image.open(io.BytesIO(base64.b64decode(paid))) as image:
        assert image.size == PREVIEW_SIZE
    assert storage.downloads == 2
