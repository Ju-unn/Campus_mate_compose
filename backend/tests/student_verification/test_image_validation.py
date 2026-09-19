from app.student_verification.image_validation import is_valid_student_id_photo

_JPEG_MAGIC = b"\xff\xd8\xff"
_PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def test_jpeg_signature_passes():
    assert is_valid_student_id_photo(_JPEG_MAGIC + b"rest-of-file")


def test_png_signature_passes():
    assert is_valid_student_id_photo(_PNG_MAGIC + b"rest-of-file")


def test_other_bytes_rejected():
    assert not is_valid_student_id_photo(b"not-an-image")


def test_oversized_file_rejected():
    oversized = _JPEG_MAGIC + b"0" * (10 * 1024 * 1024)
    assert not is_valid_student_id_photo(oversized)
