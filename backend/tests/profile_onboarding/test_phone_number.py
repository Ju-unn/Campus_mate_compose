import pytest

from app.profile_onboarding.phone_number import to_e164, to_signup_e164


def test_an_international_form_lands_on_the_same_e164_as_the_domestic_one():
    """연락처 앱은 같은 번호를 `+82 10-…` 로도 적는다. 국내 형식과 다른 값이 되면 지인 차단 해시가 빗나간다."""
    assert to_e164("+82 10-1234-5678") == "+821012345678"
    assert to_e164("+82 10-1234-5678") == to_e164("010-1234-5678")
    assert to_e164("+82 010-1234-5678") == "+821012345678"


def test_contact_numbers_keep_the_loose_rule():
    """연락처 차단 · 지인 대조는 친구 번호가 가짜 모양이어도, 옛 10자리여도 그대로 받는다 — 가입 규칙과 따로 논다."""
    assert to_e164("010-1234-5678") == "+821012345678"
    assert to_e164("010-0000-0000") == "+821000000000"
    assert to_e164("011-123-4567") == "+82111234567"


@pytest.mark.parametrize("raw", ["010-4821-7395", "01048217395", "+82 10-4821-7395", "+82 010-4821-7395"])
def test_signup_takes_a_plain_010_number_in_every_shape(raw):
    assert to_signup_e164(raw) == "+821048217395"


@pytest.mark.parametrize("raw", [
    "011-123-4567", "016-1234-5678", "019-4821-7395",  # 옛 번호(011 · 016~019)
    "010-482-7395", "010-4821-73951", "02-123-4567", "010-1", "",  # 010 + 8자리가 아님
])
def test_signup_takes_only_010_with_eight_digits(raw):
    assert to_signup_e164(raw) is None


@pytest.mark.parametrize("rest", [d * 8 for d in "0123456789"])
def test_signup_refuses_eight_same_digits(rest):
    assert to_signup_e164(f"010{rest}") is None


@pytest.mark.parametrize("rest", ["12345678", "87654321", "01234567", "98765432", "23456789", "76543210"])
def test_signup_refuses_an_eight_digit_run(rest):
    assert to_signup_e164(f"010{rest}") is None


@pytest.mark.parametrize("raw", [
    "010-1234-1234", "010-1234-1111", "010-1111-2222", "010-1212-1212", "010-0000-1234", "010-1234-0000",
])
def test_signup_refuses_the_known_fakes(raw):
    assert to_signup_e164(raw) is None


@pytest.mark.parametrize("raw", [
    "010-1234-5679",  # 가운데만 1234
    "010-4821-1234", "010-4821-0000", "010-4821-1111", "010-4821-7777",  # 끝만 골드번호
    "010-3456-3456",  # 가운데 · 끝이 같은 번호(목록에 없는 것)
    "010-0000-5678",  # 가운데 0000(규칙 D) 은 넣지 않았다
])
def test_signup_keeps_numbers_real_people_may_have(raw):
    assert to_signup_e164(raw) is not None
