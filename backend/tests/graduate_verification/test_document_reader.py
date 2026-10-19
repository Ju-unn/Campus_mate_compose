import pytest

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


# 서울대학교 졸업증명서 양식을 본뜬 글자(개인정보는 뺐다). 번호 라벨이 "원본대조번호"이고 글자 사이에 공백이 섞인다.
SNU_FORM = """[ 원본대조번호 : ABCD-1234-EF56-7890 ]
제 0000001 호
졸 업 증 명 서
대 학 및 전 공 : 예시대학 예시학부 (예시전공)
입 학 년 월 일 : 2000. 1. 1.
졸 업 년 월 일 : 2000. 2. 2.
학 위 종 별 : 예시학사
학 위 등 록 번 호 : 서울대0000(학) 0001
위의 사실을 증명합니다.
2000 년 3 월 3 일
서 울 대 학 교 교 무 처 장
※ 본 증명서는 서울대학교에서 발급되었으며 "http://www.snu.ac.kr/certificate/request" 에 접속하여 상단의 증명서 "원본대조번호"를 입력하면 증명서 원본대조 및 유효성을 검증할 수 있습니다.
"""


def test_reader_reads_number_and_school_from_the_snu_form():
    assert read_certificate(SNU_FORM, NAMES) == CertificateReading("ABCD1234EF567890", ("서울대학교",))


def test_reader_reads_the_snu_number_as_vision_returns_it():
    # 실제 Vision 은 대괄호 안쪽 공백을 지우고 글자 사이 공백도 줄여 돌려준다.
    text = "[원본대조번호: ABCD-1234-EF56-7890]\n제 0000001 호\n졸 업 증 명서\n서울대학교 교무처장"

    assert read_certificate(text, NAMES) == CertificateReading("ABCD1234EF567890", ("서울대학교",))


@pytest.mark.parametrize("label", ["원본대조번호", "원 본 대 조 번 호", "문서확인번호", "문서번호", "발급번호", "확인번호"])
def test_reader_accepts_every_known_label_even_with_spaces_between_letters(label):
    assert read_certificate(f"졸업증명서\n{label} : AB12-CD34-EF56", []).document_number == "AB12CD34EF56"


def test_reader_does_not_take_the_certificate_serial_or_degree_registration_number():
    text = "제 0000001 호\n졸 업 증 명 서\n학 위 등 록 번 호 : 서울대0000(학) 0001\n서울대학교 교무처장"

    assert read_certificate(text, NAMES) == CertificateReading(None, ("서울대학교",))


def test_reader_document_without_any_number_or_school_reads_nothing():
    assert read_certificate("제 0000001 호\n졸 업 증 명 서\n위의 사실을 증명합니다.", NAMES) == CertificateReading(None, ())
