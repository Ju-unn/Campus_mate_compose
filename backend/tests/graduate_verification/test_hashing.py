import hashlib
import hmac

from app.graduate_verification.hashing import (
    hash_document_number,
    hash_student_number,
    normalize_document_number,
    normalize_student_number,
)
from app.signup_policy import hash_email

SECRET = "identity-key-test"
UNIVERSITY = "00000000-0000-0000-0000-000000009900"


def test_hashing_is_domain_separated():
    same_text = "1234"

    hashes = {
        hash_email(SECRET, same_text),
        hash_document_number(SECRET, same_text),
        hash_student_number(SECRET, UNIVERSITY, same_text),
    }

    assert len(hashes) == 3
    assert all(len(h) == 32 for h in hashes)
    assert hash_document_number("other-key", same_text) != hash_document_number(SECRET, same_text)


def test_document_hash_uses_the_documented_prefix():
    expected = hmac.new(SECRET.encode(), b"graduate-document|ABCD1234", hashlib.sha256).digest()

    assert hash_document_number(SECRET, "abcd-1234") == expected


def test_document_number_variants_hash_the_same():
    variants = ["1234-5678 9012-3456", "1234567890123456", "  1234 5678 9012 3456 "]
    assert {normalize_document_number(v) for v in variants} == {"1234567890123456"}
    assert len({hash_document_number(SECRET, v) for v in variants}) == 1
    assert normalize_document_number("ab12-cd34") == normalize_document_number("AB12CD34") == "AB12CD34"


def test_document_number_that_is_too_short_or_not_alphanumeric_is_none():
    assert normalize_document_number("12") is None
    assert normalize_document_number("12한글34") is None
    assert normalize_document_number("") is None
    assert normalize_document_number("1" * 41) is None


def test_student_hash_depends_on_university_and_ignores_case_and_padding():
    other_university = "00000000-0000-0000-0000-000000009901"

    assert hash_student_number(SECRET, UNIVERSITY, "2019123456") != hash_student_number(
        SECRET, other_university, "2019123456")
    assert hash_student_number(SECRET, UNIVERSITY, " a2019123 ") == hash_student_number(SECRET, UNIVERSITY, "A2019123")
    assert normalize_student_number("  ") is None
    assert normalize_student_number("1" * 21) is None
    assert normalize_student_number("20-19 123") == "2019123"
