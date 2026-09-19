def matches_school_and_name(ocr_text: str, school_name: str, real_name: str) -> bool:
    normalized = _normalize(ocr_text)
    return _normalize(school_name) in normalized and _normalize(real_name) in normalized


def _normalize(value: str) -> str:
    return "".join(value.lower().split())
