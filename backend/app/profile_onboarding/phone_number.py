"""전화번호를 저장 형식(E.164)으로 맞춘다.

앱은 `010-1234-5678` 처럼 하이픈을 붙여 보여주지만 저장은 한 모양이어야 한다 —
조각 6 의 지인 차단이 E.164 로 정규화한 값에 HMAC 을 뜨기 때문에, 저장값이 그 모양과
다르면 같은 번호가 서로 다른 값으로 남아 지인 대조가 빗나간다.
바꾸는 자리는 여기 하나뿐이다(2026-09-24 대장 결정).
"""

import re

# 국내 휴대전화 번호. 010 은 11자리, 011·016~019 옛 번호는 10자리다.
_MOBILE = re.compile(r"01[0-9]{8,9}")


def to_e164(raw: str) -> str | None:
    """숫자만 남겨 검사하고 `+8210…` 으로 돌려준다. 휴대전화 번호가 아니면 `None`."""
    digits = re.sub(r"\D", "", raw)
    if digits.startswith("82"):
        # 연락처 앱의 `+82 10-…`·`+82 010-…` 는 국내 형식(010…)으로 되돌려 같은 검사를 탄다 — 지인 차단 해시가 한 모양이 된다.
        digits = "0" + digits[2:].lstrip("0")
    if not _MOBILE.fullmatch(digits):
        return None
    # 국가번호를 붙일 때 앞자리 0 은 뺀다(+82 10 1234 5678).
    return f"+82{digits[1:]}"


# ── 가입용(04-1 기본 정보) 엄격 규칙 ──────────────────────────────────────────────────────────
# 연락처 차단 · 지인 대조는 위 to_e164 를 그대로 쓴다 — 친구 번호가 가짜 모양이어도 지문 등록은 해야 한다.
# 규칙은 바탕화면 출시준비/전화번호_인증_방법_가격.md §3-1 · §3-2 A·B·C 다. 패턴 하나가 막는 번호는 1,000개 이내만
# 넣는다(§3-4) — 가운데만 1234 · 끝만 0000 같은 "골드번호" 는 진짜 사람이 써서 막지 않는다. 앱도 같은 목록이어야 한다.
# 막힐 때의 문구 · 코드는 core/errors.py PHONE_NUMBER_INVALID · CODE_PHONE_NUMBER_INVALID(422).
_SIGNUP_MOBILE = re.compile(r"\+8210(\d{8})")  # 010 + 8자리만. 011 · 016~019 옛 번호는 앱이 이미 못 받는다(§2-4)
_RUNS = ("0123456789", "9876543210")  # 뒤 8자리가 이 안에 통째로 들어 있으면 한 줄 순서다(B)
_KNOWN_FAKES = frozenset({"12341234", "12341111", "11112222", "12121212", "00001234", "12340000"})  # C


def to_signup_e164(raw: str) -> str | None:
    """가입 번호. 010 + 8자리이고 뒤 8자리가 같은 숫자(A) · 한 줄 순서(B) · 알려진 가짜(C)가 아니면 `+8210…`, 아니면 `None`."""
    e164 = to_e164(raw)
    match = _SIGNUP_MOBILE.fullmatch(e164 or "")
    if match is None:
        return None
    rest = match[1]
    if len(set(rest)) == 1 or any(rest in run for run in _RUNS) or rest in _KNOWN_FAKES:
        return None
    return e164
