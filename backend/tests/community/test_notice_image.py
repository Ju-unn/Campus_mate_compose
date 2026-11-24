"""공지 그림 검사 + 다시 저장하기(할 일 21, 보안 기준 21-3). 그림은 코드로 만든 단색 이미지만 쓴다."""
import io

import pytest
from PIL import Image

from app.community.notice_image import (
    IMAGE_TOO_LARGE, IMAGE_TYPE, LONG_SIDE, MAX_IMAGE_BYTES, ImageRejected, prepare_notice_image)


def _encode(image: Image.Image, fmt: str, **options) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, format=fmt, **options)
    return buffer.getvalue()


def _solid(size=(40, 30), mode="RGB", color=(200, 30, 30)) -> Image.Image:
    return Image.new(mode, size, color)


def _open(data: bytes) -> Image.Image:
    image = Image.open(io.BytesIO(data))
    image.load()
    return image


def _rejected(data: bytes) -> str:
    with pytest.raises(ImageRejected) as caught:
        prepare_notice_image(data)
    return caught.value.reason


@pytest.mark.parametrize("fmt", ["JPEG", "PNG", "WEBP"])
def test_jpeg_png_webp_come_back_as_jpeg(fmt):
    out = prepare_notice_image(_encode(_solid(), fmt))

    assert out.startswith(b"\xff\xd8\xff")
    assert _open(out).format == "JPEG"
    assert _open(out).size == (40, 30)


@pytest.mark.parametrize("data", [
    b'<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>',
    b"<!doctype html><html><body>hi</body></html>",
    b"",
], ids=["svg", "html", "empty"])
def test_svg_html_and_empty_are_rejected_as_image_type(data):
    assert _rejected(data) == IMAGE_TYPE


def test_gif_is_rejected_as_image_type():
    assert _rejected(_encode(_solid(mode="P", color=1), "GIF")) == IMAGE_TYPE


def test_a_broken_file_with_a_jpeg_head_is_rejected_as_image_type():
    assert _rejected(b"\xff\xd8\xff\xe0" + b"\x00garbage" * 50) == IMAGE_TYPE


def test_a_truncated_png_is_rejected_as_image_type():
    whole = _encode(_solid((200, 200), color=(10, 200, 10)), "PNG")
    assert _rejected(whole[: len(whole) // 2]) == IMAGE_TYPE


def test_png_magic_with_a_jpeg_body_is_rejected():
    # 머리는 PNG 인데 Pillow 가 연 형식은 JPEG — 매직 바이트와 실제 형식이 다르면 거절한다.
    jpeg = _encode(_solid(), "JPEG")
    assert _rejected(b"\x89PNG\r\n\x1a\n" + jpeg) == IMAGE_TYPE


def test_riff_that_is_not_webp_is_rejected():
    assert _rejected(b"RIFF\x24\x00\x00\x00WAVEfmt " + b"\x00" * 40) == IMAGE_TYPE


def test_more_than_10mb_is_rejected_as_too_large():
    assert MAX_IMAGE_BYTES == 10 * 1024 * 1024
    data = _encode(_solid(), "JPEG")
    assert _rejected(data + b"\x00" * (11 * 1024 * 1024)) == IMAGE_TOO_LARGE


def test_a_decompression_bomb_is_rejected_before_decoding():
    # 1비트 PNG 는 작은 파일로 큰 화면을 주장할 수 있다 — 화소 수 상한을 넘으면 풀기 전에 막는다.
    bomb = _encode(Image.new("1", (8000, 8000)), "PNG")
    assert len(bomb) < MAX_IMAGE_BYTES
    assert _rejected(bomb) == IMAGE_TYPE


def test_exif_including_location_is_not_kept():
    exif = Image.Exif()
    exif[0x010F] = "CameraMaker"  # Make
    exif[0x8825] = {1: "N", 2: (37.0, 33.0, 0.0)}  # GPSInfo
    original = _encode(_solid(), "JPEG", exif=exif)
    assert b"Exif" in original

    out = prepare_notice_image(original)

    assert b"Exif" not in out
    assert dict(_open(out).getexif()) == {}


def test_exif_orientation_is_applied_before_it_is_dropped():
    exif = Image.Exif()
    exif[0x0112] = 6  # 시계 방향 90도 돌려 보이기
    out = prepare_notice_image(_encode(_solid((40, 30)), "JPEG", exif=exif))

    assert _open(out).size == (30, 40)


def test_the_long_side_is_cut_to_1600():
    assert LONG_SIDE == 1600
    out = prepare_notice_image(_encode(_solid((3200, 1000)), "PNG"))

    assert _open(out).size == (1600, 500)


def test_a_tall_image_keeps_its_ratio():
    out = prepare_notice_image(_encode(_solid((900, 2400)), "WEBP"))

    assert _open(out).size == (600, 1600)


def test_a_small_image_is_not_enlarged():
    out = prepare_notice_image(_encode(_solid((1600, 20)), "PNG"))

    assert _open(out).size == (1600, 20)


def test_transparency_becomes_white():
    out = prepare_notice_image(_encode(Image.new("RGBA", (10, 10), (0, 0, 0, 0)), "PNG"))

    assert _open(out).mode == "RGB"
    assert all(channel > 245 for channel in _open(out).getpixel((5, 5)))


def test_a_palette_png_with_transparency_becomes_white():
    image = Image.new("P", (10, 10), 0)
    image.putpalette([0, 0, 0] * 256)
    out = prepare_notice_image(_encode(image, "PNG", transparency=0))

    assert all(channel > 245 for channel in _open(out).getpixel((5, 5)))
