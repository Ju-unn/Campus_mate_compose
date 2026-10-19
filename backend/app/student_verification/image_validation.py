# 업로드 사진 한 장의 한도. 라우터는 이만큼 + 1 바이트만 읽는다(photo.read(MAX_IMAGE_BYTES + 1)) — 넘었는지만 알면 된다.
MAX_IMAGE_BYTES = 10 * 1024 * 1024
_JPEG_MAGIC = b"\xff\xd8\xff"
_PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def student_id_content_type(data: bytes) -> str | None:
    """유효한 학생증 사진이면 Content-Type 을, 아니면 None 을 반환한다.
    크기·매직바이트 검증과 Content-Type 판정을 한 곳에서 해야 둘이 어긋나지 않는다."""
    if len(data) > MAX_IMAGE_BYTES:
        return None
    if data.startswith(_JPEG_MAGIC):
        return "image/jpeg"
    if data.startswith(_PNG_MAGIC):
        return "image/png"
    return None
