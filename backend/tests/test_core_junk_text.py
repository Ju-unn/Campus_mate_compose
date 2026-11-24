"""닉네임 · 학과 장난 입력 규칙(11-18 사용자: "aaa" 같은 연속 글자 · 알파벳 순서 막기)."""
import pytest

from app.core.junk_text import has_banned_word, has_letter_run
from input_rules_cases import CASES


# 예시는 앱 시험과 같이 쓰는 표(fixtures/input_rules_cases.json)에 있다.
@pytest.mark.parametrize("text", CASES["letter_run"]["run"])
def test_three_same_or_alphabet_ordered_letters_in_a_row_are_a_run(text):
    assert has_letter_run(text)


@pytest.mark.parametrize("text", CASES["letter_run"]["not_run"])
def test_two_in_a_row_or_broken_order_is_not_a_run(text):
    assert not has_letter_run(text)


@pytest.mark.parametrize("text", ["운영진친구", "ADMIN", "Campus", "관리자", "개발자", "시발", "시발점", "애미야", "Fuck", "니미"])
def test_operator_impersonation_or_profanity_anywhere_is_banned(text):
    assert has_banned_word(text)


@pytest.mark.parametrize("text", ["민지", "Jun", "바다", "하늘이", "Mina", "하니미", "니미야"])
def test_ordinary_names_are_not_banned(text):
    assert not has_banned_word(text)
