_MAX_SIZE = 10 * 1024 * 1024
_JPEG_MAGIC = b"\xff\xd8\xff"
_PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def student_id_content_type(data: bytes) -> str | None:
    """유효한 학생증 사진이면 Content-Type 을, 아니면 None 을 반환한다.
    크기·매직바이트 검증과 Content-Type 판정을 한 곳에서 해야 둘이 어긋나지 않는다."""
    if len(data) > _MAX_SIZE:
        return None
    if data.startswith(_JPEG_MAGIC):
        return "image/jpeg"
    if data.startswith(_PNG_MAGIC):
        return "image/png"
    return None
