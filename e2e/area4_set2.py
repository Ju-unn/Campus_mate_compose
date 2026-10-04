"""영역 4 SET 2차 — FAQ 21 · 친구 초대 16i · 하트 모으기 18a 입구 · 로그아웃 16g · 탈퇴 16c.
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 4 의 그 줄(10-04 갱신)이다. 앱 쪽은 frontend/integration_test/area4_set2.dart 의 같은 번호.

`python -m e2e run area4-set2` 한 번으로 돈다(폰 A 한 대). FAQ 문항은 운영 faq 표를 읽기만 한다(고치지 않는다).
"""

import re
import time

from e2e import area1, area4, notify, tools
from e2e.area1 import Check, _app, _on_phone, _one, _rows, _signed_in
from e2e.area4 import _cut, _offline, _restore, stepper
from e2e.tools import Blocked

# 21 의 탭 순서(frontend/lib/faq/model/faq_item.dart FaqCategory) — 표의 값과 화면 글자.
TABS = (('card_matching', '카드·매칭'), ('heart_payment', '하트·결제'), ('photo_profile', '사진·프로필'),
        ('friend_review', '지인 리뷰'), ('safety', '안전·신고'), ('account', '계정'))
MAIL = 'appmailerl4538@gmail.com'
TOKEN_WAIT = 30  # 로그인 뒤 기기 토큰이 서버에 올라오기를 기다리는 시간(초)
GONE_WAIT = 10  # 로그아웃 뒤 토큰 행이 지워지기를 기다리는 시간(초)


def by_category(rows):
    """탭 순서대로 {표 값: [질문(sort_order 순)]}."""
    return {wire: [r['question'] for r in sorted((r for r in rows if r['category'] == wire), key=lambda r: r['sort_order'])]
            for wire, _ in TABS}


def hits(rows, needle):
    """앱 검색과 같은 규칙 — 앞뒤 공백을 깎고 소문자로, 질문 · 답변 부분일치, 탭 순서 → sort_order 순."""
    word = needle.strip().lower()
    found = {wire: [r['question'] for r in sorted((r for r in rows if r['category'] == wire), key=lambda r: r['sort_order'])
                    if word in r['question'].lower() or word in r['answer'].lower()] for wire, _ in TABS}
    return [question for wire, _ in TABS for question in found[wire]]


def header_labels(rows, needle):
    """검색 중 보이는 묶음 머리글 — 걸린 문항이 있는 탭의 글자(탭 순서)."""
    word = needle.strip().lower()
    return [label for wire, label in TABS
            if any(r['category'] == wire and (word in r['question'].lower() or word in r['answer'].lower()) for r in rows)]


def english_word(rows):
    """질문 · 답변에서 찾은 첫 영어 단어(3자 이상). 없으면 None."""
    for row in rows:
        found = re.search(r'[A-Za-z]{3,}', row['question'] + ' ' + row['answer'])
        if found:
            return found.group()
    return None


def _faq(run):
    rows = _rows(run, 'faq?select=category,question,answer,sort_order')
    if not rows:
        raise Blocked('운영 faq 표가 비어 있음')
    return rows


def _first_tab(rows):
    return by_category(rows)['card_matching']


def _answer(rows, question):
    return next(r['answer'] for r in rows if r['question'] == question)


def _code(run, account_id):
    code = _one(run, f'profiles?id=eq.{account_id}&select=referral_code').get('referral_code')
    if not code:
        raise Blocked('추천 코드를 못 읽음')
    return code


# ── FAQ 21 ──────────────────────────────────────────────────────────────────────────────────────

def p_set_44(run, phone):
    check = Check()
    _, token = _signed_in(run, 'home')
    rows = _faq(run)
    _app(check, phone(token_hash=token, labels=[label for _, label in TABS], questions=_first_tab(rows)))
    return check.result()


def p_set_45(run, phone):
    check = Check()
    _, token = _signed_in(run, 'home')
    by = by_category(_faq(run))
    _app(check, phone(token_hash=token, expected={label: by[wire] for wire, label in TABS}))
    return check.result()


def p_set_46(run, phone):
    check = Check()
    _, token = _signed_in(run, 'home')
    rows = _faq(run)
    questions = _first_tab(rows)
    if len(questions) < 2:
        raise Blocked(f'첫 탭 문항이 {len(questions)}개 — 2개 이상 있어야 함')
    _app(check, phone(token_hash=token, questions=questions[:2], answers=[_answer(rows, q) for q in questions[:2]]))
    return check.result()


def p_set_47(run, phone):
    check = Check()
    _, token = _signed_in(run, 'home')
    rows = _faq(run)
    questions = _first_tab(rows)
    if not questions:
        raise Blocked('첫 탭 문항이 없음')
    _app(check, phone(token_hash=token, question=questions[0], answer=_answer(rows, questions[0]), other_tab=TABS[1][1]))
    return check.result()


def p_set_48(run, phone):
    check = Check()
    _, token = _signed_in(run, 'home')
    rows = _faq(run)
    expected = hits(rows, '하트')
    if not expected:
        raise Blocked('"하트" 가 든 문항이 없음 — 시나리오 가정이 어긋남')
    _app(check, phone(token_hash=token, needle='하트', expected=expected, headers=header_labels(rows, '하트')))
    return check.result()


def p_set_49(run, phone):
    check = Check()
    _, token = _signed_in(run, 'home')
    rows = _faq(run)
    word = english_word(rows)
    if word is None:
        raise Blocked('faq 36행에 영어 단어가 없음 — 대소문자 가설을 만들 수 없음')
    expected = hits(rows, word)
    variants = [{'text': '  하트  ', 'expected': hits(rows, '하트')},
                {'text': word.lower(), 'expected': expected}, {'text': word.upper(), 'expected': expected},
                {'text': word.swapcase(), 'expected': expected}]
    if not variants[0]['expected']:
        raise Blocked('"하트" 가 든 문항이 없음')
    _app(check, phone(token_hash=token, variants=variants))
    return check.result()


def p_set_50(run, phone):
    check = Check()
    _, token = _signed_in(run, 'home')
    _app(check, phone(token_hash=token, questions=_first_tab(_faq(run))))
    return check.result()


def p_set_51(run, phone):
    check = Check()
    _, token = _signed_in(run, 'home')
    needle = 'ㅋㅋㅋzzqq'
    if hits(_faq(run), needle):
        raise Blocked(f'"{needle}" 가 든 문항이 있어 결과 0개 가설을 만들 수 없음')
    _app(check, phone(token_hash=token, needle=needle))
    return check.result()


def p_set_54(run, phone):
    check = Check()
    _, token = _signed_in(run, 'home')
    rows = _faq(run)
    account = by_category(rows)['account']
    if not account:
        raise Blocked('계정 탭 문항이 없음')
    needle = account[0][:2]
    _app(check, phone(token_hash=token, tab=TABS[-1][1], needle=needle, after_clear=account))
    return check.result()


def p_set_02(run, phone):
    check = Check()
    _, token = _signed_in(run, 'home')
    _offline(phone, check, _cut(phone), token_hash=token)
    return check.result()


def p_set_03(run, phone):
    check = Check()
    _, token = _signed_in(run, 'home')
    questions = _first_tab(_faq(run))
    _app(check, phone(token_hash=token, phase='cache'), '받아 둠')
    _offline(phone, check, _cut(phone), fresh=False, phase='offline', questions=questions)
    return check.result()


# ── 친구 초대 16i ───────────────────────────────────────────────────────────────────────────────

def _invite(run):
    account, token = _signed_in(run, 'home')
    return token, _code(run, account['id'])


def _invite_case(run, phone):
    check = Check()
    token, code = _invite(run)
    _app(check, phone(token_hash=token, code=code))
    return check.result()


def p_set_60(run, phone):
    check = Check()
    token, code = _invite(run)
    text = f'CampusMate 에서 같이 해요! 가입할 때 추천 코드 {code} 를 넣어 줘.'
    note = []

    def sheet(said):
        time.sleep(3)  # 공유 창이 뜨기를 기다린다
        top = phone.top()
        check.that(tools.PACKAGE not in top, f'공유 창이 안 뜸 — 맨 앞이 아직 우리 앱({top[:80]})')
        if notify.screen_has(phone.serial, text):
            note.append('공유 창에서 초대 글 확인')
        elif 'Chooser' in top or 'Resolver' in top:  # 삼성 등은 공유 창에 미리보기를 안 그린다 — 글 자체는 invite_share_test 가 지킨다
            note.append('공유 창은 뜸 · 이 기기는 미리보기가 없어 글은 못 읽음')
        else:
            check.that(False, '공유 창에서 초대 글을 못 찾음')
        tools.adb(phone.serial, 'shell', 'input', 'keyevent', 'KEYCODE_BACK')  # 공유 창을 닫고 앱으로

    _app(check, phone(midway=stepper(phone, sheet), token_hash=token, code=code))
    return check.result('; '.join(note))


def p_set_61(run, phone):
    check = Check()
    token, code = _invite(run)
    _offline(phone, check, _cut(phone), _restore(phone), token_hash=token, code=code)
    return check.result()


# ── 로그아웃 16g · 탈퇴 16c ────────────────────────────────────────────────────────────────────

def _token_rows(run, account_id):
    return _rows(run, f'push_tokens?profile_id=eq.{account_id}&select=token')


def _wait(until, seconds):
    deadline = time.monotonic() + seconds
    while True:
        if until():
            return True
        if time.monotonic() >= deadline:
            return False
        time.sleep(2)


def _with_device_token(run, phone, account, token):
    """알림 권한을 이 앱에만 주고, 앱을 켜 홈에서 멈춘 사이 기기 토큰이 서버에 올라오기를 기다린다(안 오면 [Blocked]).
    끝나면 권한을 되돌린다. 앱이 끝나고 난 뒤의 말은 [Check] 에 담겨 돌아온다."""
    check = Check()

    def token_arrives(said):
        if not _wait(lambda: _token_rows(run, account['id']), TOKEN_WAIT):
            raise Blocked(f'{TOKEN_WAIT}초 안에 기기 토큰이 서버에 안 올라옴 — 알림 권한 · FCM 확인')

    notify.grant_notifications(phone.serial)
    try:
        _app(check, phone(midway=stepper(phone, token_arrives), token_hash=token))
    finally:
        notify.revoke_notifications(phone.serial)
    return check


def p_set_65(run, phone):
    account, token = _signed_in(run, 'home')
    check = _with_device_token(run, phone, account, token)
    # 시나리오는 "5초 안 로그인 화면" — 앱은 15초까지 기다리고 걸린 시간을 메모로 남긴다(참고용).
    gone = _wait(lambda: not _token_rows(run, account['id']), GONE_WAIT)
    check.that(gone, f'로그아웃 뒤 {GONE_WAIT}초가 지나도 push_tokens 행이 남음')
    return check.result()


def p_set_66(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    second = run.account('home')
    nickname = _one(run, f"profiles?id=eq.{account['id']}&select=nickname").get('nickname')
    if not nickname:
        raise Blocked('앞 계정 닉네임을 못 읽음')
    _app(check, phone(token_hash=token, second=run.link(second['email']), nick=nickname))
    return check.result()


def p_set_68(run, phone):
    check = Check()
    _, token = _signed_in(run, 'home')
    _offline(phone, check, _cut(phone), token_hash=token)
    return check.result()


def _profile_value(run, account_id, field):
    return _one(run, f'profiles?id=eq.{account_id}&select={field}').get(field)


def p_set_69(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    _app(check, phone(token_hash=token))
    # 앱 토글은 서버 응답 전에 먼저 바뀐다(낙관적 갱신) — 서버 저장이 끝나기를 잠깐 기다린다.
    _wait(lambda: _profile_value(run, account['id'], 'matching_paused') is True, GONE_WAIT)
    check.that(_profile_value(run, account['id'], 'matching_paused') is True, 'matching_paused 가 true 가 아님')
    status = _profile_value(run, account['id'], 'status')
    check.that(status == 'active', f'계정 status 가 {status!r}(기대 active)')
    return check.result()


def p_set_70(run, phone):
    account, token = _signed_in(run, 'home')
    check = _with_device_token(run, phone, account, token)  # 토큰이 처음부터 없으면 "지워졌다" 가 아무것도 증명하지 못한다
    status = _profile_value(run, account['id'], 'status')
    check.that(status == 'withdrawn', f'계정 status 가 {status!r}(기대 withdrawn)')
    check.that(not _token_rows(run, account['id']), '탈퇴했는데 push_tokens 행이 남음')
    return check.result()


PHONE = {
    'E-SET-02': p_set_02, 'E-SET-03': p_set_03, 'E-SET-44': p_set_44, 'E-SET-45': p_set_45, 'E-SET-46': p_set_46,
    'E-SET-47': p_set_47, 'E-SET-48': p_set_48, 'E-SET-49': p_set_49, 'E-SET-50': p_set_50, 'E-SET-51': p_set_51,
    'E-SET-54': p_set_54,
    'E-SET-58': _invite_case, 'E-SET-59': _invite_case, 'E-SET-60': p_set_60, 'E-SET-61': p_set_61, 'E-SET-62': _invite_case,
    'E-SET-63': _on_phone('home'), 'E-SET-64': _on_phone('home'), 'E-SET-65': p_set_65, 'E-SET-66': p_set_66,
    'E-SET-68': p_set_68, 'E-SET-69': p_set_69, 'E-SET-70': p_set_70,
}

area1.PHONE.update(PHONE)
area1.BUNDLES['area4-set2'] = list(PHONE)
