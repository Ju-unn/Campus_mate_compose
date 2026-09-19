from app.student_verification.matching import matches_school_and_name

OCR_TEXT = """학생증
한국대학교
컴퓨터공학과
홍길동
2024학년도
"""


def test_school_and_name_both_present_returns_true():
    assert matches_school_and_name(OCR_TEXT, "한국대학교", "홍길동")


def test_only_school_present_returns_false():
    assert not matches_school_and_name(OCR_TEXT, "한국대학교", "김철수")


def test_only_name_present_returns_false():
    assert not matches_school_and_name(OCR_TEXT, "미국대학교", "홍길동")


def test_whitespace_and_newlines_in_ocr_text_still_matches():
    noisy_text = "학생증\n\n  한국   대학교  \n 홍   길동 \n2024학년도"
    assert matches_school_and_name(noisy_text, "한국대학교", "홍길동")


def test_english_school_name_is_case_insensitive():
    ocr_text = "STUDENT ID\nSEOUL NATIONAL UNIVERSITY\nHONG GILDONG\n2024"
    assert matches_school_and_name(ocr_text, "Seoul National University", "Hong Gildong")
