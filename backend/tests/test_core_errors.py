"""사용자에게 나가는 detail 문구(core/errors.py)의 글자 규칙."""
from app.core import errors


def test_try_again_wording_says_jamsi_hu():
    # 사용자 결정(2026-11-10): "잠시 뒤" 가 아니라 "잠시 후" — 앱 문구(ARB)와 같은 글자.
    texts = {name: value for name, value in vars(errors).items() if name.isupper() and isinstance(value, str)}
    assert texts
    assert {name: text for name, text in texts.items() if "잠시 뒤" in text} == {}
