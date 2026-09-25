from app.student_verification.matching import missing_from_student_id

OCR_TEXT = """학생증
한국대학교
컴퓨터공학과
홍길동
2024학년도
"""


def test_school_and_name_both_present_returns_no_reason():
    assert missing_from_student_id(OCR_TEXT, "한국대학교", "홍길동") is None


def test_only_school_present_reports_the_missing_name():
    assert missing_from_student_id(OCR_TEXT, "한국대학교", "김철수") == "name_not_found"


def test_only_name_present_reports_the_missing_school():
    assert missing_from_student_id(OCR_TEXT, "미국대학교", "홍길동") == "school_not_found"


def test_neither_present_reports_both():
    assert missing_from_student_id(OCR_TEXT, "미국대학교", "김철수") == "both_not_found"


def test_empty_ocr_text_reports_no_text():
    # Vision 이 답은 했는데 글자가 하나도 없는 경우다 — "대조 실패"와는 손볼 곳이 다르다.
    assert missing_from_student_id("", "한국대학교", "홍길동") == "no_text"
    assert missing_from_student_id("  \n ", "한국대학교", "홍길동") == "no_text"


def test_whitespace_and_newlines_in_ocr_text_still_matches():
    noisy_text = "학생증\n\n  한국   대학교  \n 홍   길동 \n2024학년도"
    assert missing_from_student_id(noisy_text, "한국대학교", "홍길동") is None


def test_english_school_name_is_case_insensitive():
    ocr_text = "STUDENT ID\nSEOUL NATIONAL UNIVERSITY\nHONG GILDONG\n2024"
    assert missing_from_student_id(ocr_text, "Seoul National University", "Hong Gildong") is None
