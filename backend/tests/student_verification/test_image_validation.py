from app.student_verification.image_validation import student_id_content_type

_JPEG_MAGIC = b"\xff\xd8\xff"
_PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def test_jpeg_signature_passes():
    assert student_id_content_type(_JPEG_MAGIC + b"rest-of-file") == "image/jpeg"


def test_png_signature_passes():
    assert student_id_content_type(_PNG_MAGIC + b"rest-of-file") == "image/png"


def test_other_bytes_rejected():
    assert student_id_content_type(b"not-an-image") is None


def test_oversized_file_rejected():
    oversized = _JPEG_MAGIC + b"0" * (10 * 1024 * 1024)
    assert student_id_content_type(oversized) is None
