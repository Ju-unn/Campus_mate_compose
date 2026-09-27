from app.profile_onboarding.phone_number import to_e164


def test_an_international_form_lands_on_the_same_e164_as_the_domestic_one():
    """연락처 앱은 같은 번호를 `+82 10-…` 로도 적는다. 국내 형식과 다른 값이 되면 지인 차단 해시가 빗나간다."""
    assert to_e164("+82 10-1234-5678") == "+821012345678"
    assert to_e164("+82 10-1234-5678") == to_e164("010-1234-5678")
    assert to_e164("+82 010-1234-5678") == "+821012345678"
