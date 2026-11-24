from app.core.image_magic import JPEG_MAGIC, PNG_MAGIC, sniff_image_type

# 머리 값은 시험이 따로 적는다 — 공용 상수를 고쳐도 시험이 같이 바뀌지 않게.
_JPEG = b"\xff\xd8\xff"
_PNG = b"\x89PNG\r\n\x1a\n"


def test_jpeg_header_is_jpeg():
    assert sniff_image_type(_JPEG + b"rest") == "image/jpeg"


def test_png_header_is_png():
    assert sniff_image_type(_PNG + b"rest") == "image/png"


def test_webp_is_not_shared():
    # WEBP 는 공지만 받는다 — 공용 판정이 WEBP 를 받으면 학생증이 WEBP 를 받게 된다.
    assert sniff_image_type(b"RIFF\x00\x00\x00\x00WEBPVP8 ") is None


def test_cut_header_is_none():
    assert sniff_image_type(_JPEG[:2]) is None
    assert sniff_image_type(_PNG[:7]) is None
    assert sniff_image_type(b"") is None


def test_constants_are_the_file_headers():
    assert (JPEG_MAGIC, PNG_MAGIC) == (_JPEG, _PNG)
