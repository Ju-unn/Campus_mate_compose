"""올린 그림의 머리(매직 바이트) 판정 한 곳. 학생증 사진 · 공지 그림(할 일 21)이 같이 쓴다 — 머리 값이 두 곳에 있으면 어긋난다.
WEBP 는 공지만 받아 여기 두지 않는다(community/notice_image.py) — 여기 두면 학생증도 WEBP 를 받게 된다."""
JPEG_MAGIC = b"\xff\xd8\xff"
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def sniff_image_type(data: bytes) -> str | None:
    """머리가 JPEG 면 "image/jpeg", PNG 면 "image/png", 아니면 None. 크기 · 내용 검사는 부르는 쪽 몫이다."""
    if data.startswith(JPEG_MAGIC):
        return "image/jpeg"
    if data.startswith(PNG_MAGIC):
        return "image/png"
    return None
