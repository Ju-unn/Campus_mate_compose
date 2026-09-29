from typing import Literal

# 약관(노션 "약관동의")을 고치면 이 값만 올린다 — 이미 가입한 계정은 모두 02-c-4(재동의)로 간다.
CONSENT_VERSION = "2026-09-29"

# 앱 frontend/lib/consent/model/consent_item.dart 의 wireName 과 같은 글자다. 마케팅(선택)은
# 여기 없다 — notification_settings.marketing 이 따로 맡는다(계획서 Q4).
# enum consent_kind 의 sensitive_religion · overseas_transfer 는 09-29 결정으로 안 받음(종교는 개인정보
# 수집·이용 안에, OpenAI 국외 이전은 처리방침 공개로 대신) — 운영에 적용된 enum 이라 값만 남아 있다.
REQUIRED_KINDS = frozenset({"terms", "privacy"})


def consent_state(rows: list[dict]) -> Literal["none", "outdated", "current"]:
    """user_consents 행(kind · version)으로 이번 판 동의가 끝났는지 본다. 옛 판만 있으면 재동의다."""
    agreed_now = {row["kind"] for row in rows if row["version"] == CONSENT_VERSION}
    if REQUIRED_KINDS <= agreed_now:
        return "current"
    return "outdated" if rows else "none"
