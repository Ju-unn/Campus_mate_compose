_MAX_SIZE = 10 * 1024 * 1024
_JPEG_MAGIC = b"\xff\xd8\xff"
_PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def is_valid_student_id_photo(data: bytes) -> bool:
    if len(data) > _MAX_SIZE:
        return False
    return data.startswith(_JPEG_MAGIC) or data.startswith(_PNG_MAGIC)
