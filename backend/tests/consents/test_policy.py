from app.consents.policy import CONSENT_VERSION, REQUIRED_KINDS, consent_state

# 앱 frontend/lib/consent/model/consent_item.dart 의 wireName 과 같은 글자여야 한다(언어가 달라 양쪽에 적는다).
ALL = ["terms", "privacy", "sensitive_religion", "overseas_transfer"]


def test_required_kinds_are_the_four_wire_names():
    assert REQUIRED_KINDS == frozenset(ALL)


def test_no_rows_is_none():
    assert consent_state([]) == "none"


def test_all_four_of_current_version_is_current():
    assert consent_state([{"kind": k, "version": CONSENT_VERSION} for k in ALL]) == "current"


def test_old_version_only_is_outdated():
    # 약관을 고쳐 판이 올라가면 이미 가입한 계정은 02-c-4(재동의)로 간다.
    assert consent_state([{"kind": k, "version": "2000-01-01"} for k in ALL]) == "outdated"


def test_missing_one_required_kind_is_not_current():
    rows = [{"kind": k, "version": CONSENT_VERSION} for k in ALL[:3]]
    assert consent_state(rows) == "outdated"
