"""영역 2 폰 A 한 대 — 1차 16(홈 09b · 추천 시트 16i · 알림 설정 16d · 하트 목록 18a/18b 읽기).
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 2 의 그 줄이다. 앱 쪽은 frontend/integration_test/area2.dart 의 같은 번호.

폰 가설은 area1.PHONE 에 더해 `python -m e2e run area2-phone-a` 한 번으로 돈다. 계정은 `run.account('home')`(온보딩 끝 · active),
판정은 앱이 하고 DB 값은 여기서 본다. 쓰기는 이번 실행이 만든 계정 id 에만(area2._guard). 운영 시험대학 행은 읽기만 한다.
"""

import re

from e2e import area1, tools
from e2e.area1 import Check, _api, _app, _on_phone, _one, _patch, _rows, _signed_in, _test_university
from e2e.area2 import _guard
from e2e.tools import Blocked

REFERRAL_CODE = re.compile(r'[A-HJ-NP-Z2-9]{6}')  # profiles_referral_code_format — 0 · O · 1 · I 없음
KNOWN_MOCK = '목값이 운영에 나가 있음(known A2)'  # 사용자 결정 10-01 (가): 심사 때 숨김, 지금은 보이는 것이 정상
# 홈 완성도(backend/app/home/completion.py) 넷 — 하나 채울 때마다 10. 사진은 API 로 셋째 장, 나머지는 프로필 값을 바로 쓴다.
FILLS = {
    'mbti': {'mbti': 'ENFP'},
    'height': {'preferred_height_min': 160, 'preferred_height_max': 185},
    'interests': {'interest_tags': ['카페가기', '자전거', '패션', '산책', '영화']},
}
STAT_LABELS = ('전달된 카드', '가입 수', '시작된 대화')  # home_screen.dart StatTile label — 앱이 이 이름으로 말한다


# ── 홈 09b ──────────────────────────────────────────────────────────────────────────────────────────

def _school(run):
    school = _test_university(run)
    if not school:
        raise Blocked('시험대학 행을 못 찾음')
    return _one(run, f'universities?id=eq.{school}&select=card_opens_at,name')


def p_home_01(run, phone):
    """학교가 이미 열려(card_opens_at = null) 있어야 09b 가 보인다 — 운영 값은 바꾸지 않고, 아니면 계정도 안 만들고 blocked."""
    opens = _school(run).get('card_opens_at')
    if opens is not None:
        raise Blocked(f'시험대학 card_opens_at = {opens} — null 이어야 한다(운영 값은 안 바꾼다)')
    return _on_phone('home')(run, phone)


def _count(run, path):
    """PostgREST 전체 건수(Prefer count=exact → Content-Range 의 / 뒤)."""
    reply = tools.call('GET', f"{run.cfg['SUPABASE_URL']}/rest/v1/{path}&limit=1",
                       {'apikey': run.key, 'Authorization': f'Bearer {run.key}', 'Prefer': 'count=exact'})
    total = reply.headers.get('content-range', '').rpartition('/')[2]
    if reply.status >= 300 or not total.isdigit():
        raise Blocked(f'{path} 세기 {reply.status}')
    return int(total)


def _stats(run):
    """home_stats 와 같은 뜻을 따로 센다 — 카드 전체 · active 프로필 · 사람이 쓴 말풍선(text)이 한 건이라도 있는 매칭."""
    return (_count(run, 'daily_cards?select=id'),
            _count(run, 'profiles?select=id&status=eq.active'),
            _count(run, 'matches?select=id,messages!inner(id)&messages.kind=eq.text'))


def _numbers(reply):
    body = reply[1] if reply[0] == 200 and isinstance(reply[1], dict) else {}
    return tuple(body.get(k) for k in ('delivered_cards', 'signups', 'conversations_started'))


def p_home_02(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    before = _stats(run)
    summary = _numbers(_api(run, 'GET', '/home/summary', account['token']))
    said = _app(check, phone(token_hash=token))
    # ponytail: 시험 중엔 실사용자가 없어 값이 안 움직인다 — 그 사이 바뀌었으면 앱이 끝난 뒤 값과 맞춰 본다.
    db = before if summary == before else _stats(run)
    check.that(summary == db, f'/home/summary {summary} ≠ DB {db}')
    if said.get('result') == 'pass':
        if db == (0, 0, 0):
            check.that(said.get('empty') is True, f'DB 가 전부 0 인데 "첫 기록이 쌓이는 중이에요" 판이 아님 {said.get("stats")}')
        else:
            got = said.get('stats') or {}
            for label, n in zip(STAT_LABELS, db):
                check.that(got.get(label) == f'{n:,}', f'{label} 화면 {got.get(label)!r} ≠ DB {n:,}')
    return check.result()


def p_home_03(run, phone):
    check = Check()
    _, token = _signed_in(run, 'home')
    # home_stats 의 array_agg(... order by name) 와 같은 정렬 — 이름 비교는 DB 정렬 규칙(collation)에 맡긴다.
    names = [r['name'] for r in _rows(run, 'universities?select=name,profiles!inner(id)&profiles.status=eq.active&order=name.asc')]
    test_school = _school(run).get('name')
    said = _app(check, phone(token_hash=token))
    check.that(test_school in names, f'참여 중인 대학 DB 목록에 시험대학 {test_school!r} 없음 {names}')
    if said.get('result') == 'pass':
        check.that(said.get('campuses') == names, f'칩 순서 {said.get("campuses")} ≠ DB {names}')
    return check.result()


def _fill(run, account, what):
    _guard(run, account['id'])
    if what == 'photo':  # 자리 0 · 1 은 계정 공장이 올렸다
        reply = tools.form(f"{run.cfg['API_BASE_URL']}/profile-onboarding/photos", account['token'],
                           {'position': 2, 'is_avatar_source': 'false'}, ('photo', 'e2e2.png', tools.PHOTO.read_bytes(), 'image/png'))
        if reply[0] >= 300:
            raise Blocked(f'사진 셋째 장 {reply[0]} {reply[1]}')
    else:
        _patch(run, f"profiles?id=eq.{account['id']}", FILLS[what])


def p_home_04(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    me = _one(run, f"profiles?id=eq.{account['id']}"
                   '&select=mbti,preferred_height_min,preferred_height_max,interest_tags,profile_photos(count)')
    start = ((me.get('profile_photos') or [{}])[0].get('count'), me.get('mbti'), me.get('preferred_height_min'),
             me.get('preferred_height_max'), len(me.get('interest_tags') or []))
    if start != (2, None, None, None, 3):
        raise Blocked(f'홈 계정 시작값이 (사진 2, MBTI 없음, 선호 키 없음 둘, 관심사 3) 이 아님 {start}')
    _app(check, phone(token_hash=token, percent=60))
    return check.result()


def p_home_05(run, phone):
    """채우고 앱을 새로 켜기를 세 번 — 앱은 켤 때만 요약을 읽으므로 midway 보다 재시작이 시나리오("매번 앱 재시작") 그대로다."""
    check = Check()
    account, token = _signed_in(run, 'home')
    for n, (what, percent) in enumerate((('photo', 70), ('mbti', 80), ('height', 90))):
        _fill(run, account, what)
        _app(check, phone(**({'token_hash': token} if n == 0 else {'fresh': False}), percent=percent), f'{percent}%')
    return check.result()


def p_home_06(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    for what in ('photo', 'mbti', 'height', 'interests'):
        _fill(run, account, what)
    _app(check, phone(token_hash=token, percent=100))
    return check.result()


def p_home_12(run, phone):
    """리뷰 띠 "4.8" · "(143명 평가)" 는 앱이 본다. 레일 그림은 앱이 말한 경로가 앱 안 에셋인지 여기서 본다."""
    check = Check()
    _, token = _signed_in(run, 'home')
    said = _app(check, phone(token_hash=token))
    if said.get('result') == 'pass':
        rail = said.get('rail') or []
        check.that(rail and all(str(p).startswith('assets/') for p in rail), f'레일 그림이 앱 에셋이 아님 {rail}')
    return check.result(KNOWN_MOCK)


# ── 알림 설정 16d ───────────────────────────────────────────────────────────────────────────────────

def p_card_21(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    if _rows(run, f"notification_settings?profile_id=eq.{account['id']}&select=profile_id"):
        raise Blocked('새 계정인데 notification_settings 행이 있음 — 기본값을 볼 수 없다')
    _app(check, phone(token_hash=token))
    return check.result()


# ── 추천 시트 16i ───────────────────────────────────────────────────────────────────────────────────

def _db_code(run, account, check):
    code = _one(run, f"profiles?id=eq.{account['id']}&select=referral_code").get('referral_code') or ''
    check.that(REFERRAL_CODE.fullmatch(code), f'DB 코드 {code!r} 가 대문자 · 숫자 6자(0 · O · 1 · I 없음)가 아님')
    return code


def p_ref_01(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    said = _app(check, phone(token_hash=token))
    code = _db_code(run, account, check)
    if said.get('result') == 'pass':
        check.that(said.get('code') == code, f'시트 코드 {said.get("code")!r} ≠ DB {code!r}')
    return check.result()


def p_ref_02(run, phone):
    """첫 켬에서 열기 · 닫고 다시 열기, 다시 켬에서 같은 둘 — 앱이 연 때마다 읽은 코드를 모두 말한다."""
    check = Check()
    account, token = _signed_in(run, 'home')
    codes = []
    for label, job in (('첫 켬', {'token_hash': token}), ('다시 켬', {'fresh': False})):
        codes += _app(check, phone(**job), label).get('codes') or []
    code = _db_code(run, account, check)
    check.that(len(codes) >= 3, f'시트를 연 횟수 {len(codes)}(기대 3 이상)')
    check.that(all(c == code for c in codes), f'코드 {codes} — DB {code!r} 와 다른 것이 있음')
    return check.result()


def p_ref_03(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    said = _app(check, phone(token_hash=token))
    code = _db_code(run, account, check)
    if said.get('result') == 'pass':
        check.that(said.get('code') == code, f'시트 코드 {said.get("code")!r} ≠ DB {code!r}')
        check.that(said.get('clipboard') == code, f'클립보드 {said.get("clipboard")!r} ≠ 코드 {code!r}')
    return check.result()


PHONE = {
    'E-HOME-01': p_home_01, 'E-HOME-02': p_home_02, 'E-HOME-03': p_home_03, 'E-HOME-04': p_home_04,
    'E-HOME-05': p_home_05, 'E-HOME-06': p_home_06, 'E-HOME-10': _on_phone('home'), 'E-HOME-11': _on_phone('home'),
    'E-HOME-12': p_home_12,
    'E-REF-01': p_ref_01, 'E-REF-02': p_ref_02, 'E-REF-03': p_ref_03,
    'E-CARD-21': p_card_21,
    'E-HEART-01': _on_phone('home'), 'E-HEART-02': _on_phone('home'), 'E-HEART-03': _on_phone('home'),
}

area1.PHONE.update(PHONE)
area1.BUNDLES['area2-phone-a'] = list(PHONE)
