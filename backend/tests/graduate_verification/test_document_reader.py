from app.graduate_verification.document_reader import CertificateReading, read_certificate

NAMES = ["서울대학교", "서울과학기술대학교"]


def test_reader_takes_number_after_label_on_same_or_next_line():
    same_line = "졸업증명서\n문서확인번호 : 1234-5678-9012-3456\n발급일 2024.02.20"
    next_line = "졸업증명서\n문서확인번호\n1234 5678 9012 3456\n서울대학교"

    assert read_certificate(same_line, NAMES).document_number == "1234567890123456"
    assert read_certificate(next_line, NAMES).document_number == "1234567890123456"


def test_reader_accepts_the_other_labels():
    assert read_certificate("확인번호: AB12-CD34", []).document_number == "AB12CD34"
    assert read_certificate("발급번호 20240220-0001", []).document_number == "202402200001"


def test_reader_without_a_label_has_no_number():
    assert read_certificate("졸업증명서 1234-5678-9012-3456", NAMES).document_number is None


def test_reader_never_takes_a_number_from_unrelated_digits():
    text = "서울대학교 졸업증명서\n전화 02-880-5114\n발급일 2024.02.20\n학번 2019-12345"

    assert read_certificate(text, NAMES).document_number is None


def test_reader_finds_school_names_contained_ignoring_spaces():
    reading = read_certificate("서 울 대 학 교\n졸업증명서", NAMES)

    assert reading.school_names == ("서울대학교",)


def test_reader_keeps_only_the_longest_overlapping_school_name():
    names = ["서울대학교", "서울대학교사범대", "서울과학기술대학교"]

    reading = read_certificate("서울대학교사범대 졸업증명서", names)

    assert reading.school_names == ("서울대학교사범대",)


def test_reader_on_empty_text():
    assert read_certificate("", NAMES) == CertificateReading(None, ())
