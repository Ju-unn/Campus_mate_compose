"""E-REF-06 — 새 사람(B)이 가입 마지막(화면 20)에서 코드 주인(A)의 추천 코드를 넣으면 그 자리에서 둘 다 50하트.

화면 흐름은 영역 1 E-ONB-60 과 같아 앱 쪽은 그 가설을 그대로 쓴다(frontend/integration_test/e2e_test.dart 의 `E-REF-06` → `E-ONB-60`):
앱이 B 로 06-3 까지 마친 뒤 20 에서 코드를 넣고 "코드 확인하기" → 20b 리뷰 시트를 닫고 → 20d. 시나리오의 "두 기기" 중 코드 주인(A)의 화면은 이 가설이 보지 않아
**단일 폰 방식**이다 — PC 가 A 를 API 로 맡는다(활성 계정 · 코드 읽기). E-ONB-60 과 다른 점은 판정이다: 시나리오 E-REF-06 이 말한 "원장 reason=referral(ref=B id)" 를
읽는다(E-ONB-60 은 금액만 본다) — 새 사람 B 의 id 가 두 원장 줄의 ref_id 다(`redeem_referral` 의 grant_hearts 두 번, create_referrals.sql:104-105).
"""

from e2e import area1
from e2e.area1 import Check, _app, _rows, _signed_in
from e2e.area1_b2 import _referrer

FIFTY = 50


def _ledger(run, account_id):
    """그 사람의 추천 보상 원장 줄 — [(금액, ref_id)]."""
    rows = _rows(run, f'heart_transactions?profile_id=eq.{account_id}&reason=eq.referral&select=amount,ref_id')
    return [(row['amount'], row['ref_id']) for row in rows]


def p_ref_06(run, phone):
    check = Check()
    owner, code = _referrer(run)  # A — 코드 주인(활성 계정)
    newcomer, token = _signed_in(run, 'ideal_note')  # B — 학생증 verified · 학과 입력 뒤 06-3 직후(가입 마지막)
    _app(check, phone(token_hash=token, code=code))
    rows = _rows(run, f"referrals?referee_id=eq.{newcomer['id']}&select=referrer_id")
    check.that(rows == [{'referrer_id': owner['id']}], f'referrals(B 가 받은 쪽) {rows}(기대 A 한 줄)')
    given = _rows(run, f"referrals?referrer_id=eq.{owner['id']}&select=referee_id")
    check.that(given == [{'referee_id': newcomer['id']}], f'referrals(A 가 준 쪽) {given}(기대 B 한 줄 — 총 1행)')
    for who, account in (('새 사람 B', newcomer), ('코드 주인 A', owner)):
        got = _ledger(run, account['id'])
        check.that(got == [(FIFTY, newcomer['id'])], f'{who} 원장 {got}(기대 [(+{FIFTY}, ref=B id)])')
    return check.result()


PHONE = {'E-REF-06': p_ref_06}
area1.PHONE.update(PHONE)
area1.BUNDLES['area2-ref06'] = list(PHONE)
