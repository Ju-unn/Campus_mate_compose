"""자유 글(자기소개 · "이런 사람이 좋아요")의 줄 바꿈 규칙. 앱은 300자 · 6~8줄로 막고(2026-10-14 사용자 결정 "추천대로"),
서버는 옛 앱 · 직접 호출 방어용으로 1000자 · 40줄까지 넉넉하게 받는다 — 그 전에 쓴 긴 소개를 지키려고 1000 은 그대로다."""
import pytest
from pydantic import ValidationError

from app.me.schemas import ProfileUpdateRequest
from app.profile_onboarding.schemas import FREE_TEXT_MAX_LINES, BioRequest, IdealNoteRequest

_MODELS = [
    pytest.param(lambda text: BioRequest(bio=text).bio, id="onboarding-bio"),
    pytest.param(lambda text: IdealNoteRequest(note=text).note, id="ideal-note"),
    pytest.param(lambda text: ProfileUpdateRequest(bio=text).bio, id="me-bio"),
]


def test_the_line_cap_is_a_fortieth_of_the_thousand_character_cap():
    assert FREE_TEXT_MAX_LINES == 40


@pytest.mark.parametrize("parse", _MODELS)
def test_windows_and_old_mac_line_endings_become_newlines(parse):
    assert parse("말이 잘 통하는\r\n사람이\r좋아요") == "말이 잘 통하는\n사람이\n좋아요"


@pytest.mark.parametrize("parse", _MODELS)
def test_crlf_counts_as_one_character_toward_the_thousand(parse):
    # 49자 × 20줄 = 980자 + 줄 바꿈 19개. \r\n 을 두 글자로 세면 1018 이라 막히고, 한 글자로 세면 999 라 들어간다.
    text = "\r\n".join(["가" * 49] * 20)
    assert len(parse(text)) == 999


@pytest.mark.parametrize("parse", _MODELS)
def test_forty_lines_are_accepted(parse):
    assert parse("\n".join(["가나다라마바사아자차"] * 40)).count("\n") == 39


@pytest.mark.parametrize("parse", _MODELS)
def test_forty_one_lines_are_rejected(parse):
    with pytest.raises(ValidationError):
        parse("\n".join(["가나다라마바사아자차"] * 41))


@pytest.mark.parametrize("parse", _MODELS)
def test_a_thousand_and_one_characters_are_still_rejected(parse):
    with pytest.raises(ValidationError):
        parse("가" * 1001)
