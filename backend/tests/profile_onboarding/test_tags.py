import pytest

from app.profile_onboarding.tags import INTEREST_TAGS, MY_TRAITS, IDEAL_TRAITS, validate_tag_selection


def test_validate_tag_selection_rejects_unknown_tag():
    with pytest.raises(ValueError, match="목록에 없는 태그"):
        validate_tag_selection(INTEREST_TAGS, ["없는태그"])


def test_validate_tag_selection_rejects_too_few():
    with pytest.raises(ValueError, match="최소 3개"):
        validate_tag_selection(INTEREST_TAGS, INTEREST_TAGS[:2])


def test_validate_tag_selection_rejects_too_many():
    with pytest.raises(ValueError, match="최대 5개"):
        validate_tag_selection(INTEREST_TAGS, INTEREST_TAGS[:6])


def test_validate_tag_selection_accepts_valid_range():
    validate_tag_selection(INTEREST_TAGS, INTEREST_TAGS[:3])


def test_interest_tags_pool_size():
    assert len(INTEREST_TAGS) == 45


def test_my_traits_pool_size():
    assert len(MY_TRAITS) == 46


def test_ideal_traits_pool_size():
    assert len(IDEAL_TRAITS) == 44


def test_ideal_traits_typo_is_fixed():
    assert "리더십 있는" in IDEAL_TRAITS
    assert "리더쉽 있는" not in IDEAL_TRAITS
