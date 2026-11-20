"""닉네임 · 학과 장난 입력 규칙(11-18 사용자: "aaa" 같은 연속 글자 · 알파벳 순서 막기)."""
import pytest

from app.core.junk_text import has_banned_word, has_letter_run


@pytest.mark.parametrize("text", ["aaa", "AAa", "가가가", "abbb", "abc", "XYZ", "cba", "Abcd", "컴공..."])
def test_three_same_or_alphabet_ordered_letters_in_a_row_are_a_run(text):
    assert has_letter_run(text)


@pytest.mark.parametrize("text", ["진진", "복복", "땅땅이", "양아아", "hy", "가나", "abd", "Computer Science", "AI융합학부"])
def test_two_in_a_row_or_broken_order_is_not_a_run(text):
    assert not has_letter_run(text)


@pytest.mark.parametrize("text", ["운영진친구", "ADMIN", "Campus", "관리자", "개발자", "시발", "Fuck"])
def test_operator_impersonation_or_profanity_anywhere_is_banned(text):
    assert has_banned_word(text)


@pytest.mark.parametrize("text", ["민지", "Jun", "바다", "하늘이", "Mina"])
def test_ordinary_names_are_not_banned(text):
    assert not has_banned_word(text)
