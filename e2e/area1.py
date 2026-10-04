"""영역 1 묶음 1 — API 가설 19(진행만, 폰 없음). 기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 1 의 그 줄이다.

가설 하나 = 함수 하나 `(run) -> (결과, 메모)`. 계정은 [Run.account] 로 그때그때 새로 만든다(별칭 번호는 다시 안 쓴다).
"""

import base64
import re
import time
import uuid
from datetime import datetime, timedelta, timezone

from e2e import tools
from e2e.tools import Blocked

SEOUL = timezone(timedelta(hours=9))  # 서버 나이 계산(core/time.py)과 같은 날짜

REJECTED = '허용되지 않은 학교 이메일이에요'
SV_REQUIRED = '학생증 인증을 먼저 끝내 주세요'
CONSENT_REQUIRED = '약관 동의를 먼저 해 주세요'
INVALID_INPUT = '입력한 값을 다시 확인해 주세요'
TINY_JPEG = b'\xff\xd8\xff\xe0' + bytes(16) + b'\xff\xd9'  # 동의 확인이 사진보다 먼저라 내용은 상관없다


def _detail(body):
    """FastAPI `detail`(글자 · 검증 오류 목록) 또는 GoTrue `msg` → 글자."""
    if not isinstance(body, dict):
        return body
    detail = body.get('detail', body.get('msg', body.get('message')))
    if isinstance(detail, list):
        return ' / '.join(str(d.get('msg', d)) if isinstance(d, dict) else str(d) for d in detail)
    return detail


class Check:
    """어긋난 것을 모아 마지막에 한 번 판정한다 — 메모에 무엇이 어긋났는지 다 남는다."""

    def __init__(self):
        self.problems = []

    def reply(self, label, reply, status, detail=None, contains=None):
        got, body = reply
        if got != status:
            self.problems.append(f'{label}: {got}(기대 {status}) {_detail(body)}')
        elif detail is not None and _detail(body) != detail:
            self.problems.append(f'{label}: 문구 {_detail(body)!r}')
        elif contains is not None and contains not in str(_detail(body)):
            self.problems.append(f'{label}: 문구 {_detail(body)!r}')

    def that(self, ok, problem):
        if not ok:
            self.problems.append(problem)

    def result(self, note=''):
        return ('fail', '; '.join(self.problems)) if self.problems else ('pass', note)


def _api(run, method, path, token, body=None):
    return tools.api(run.cfg, method, path, token, body)


def _rows(run, path):
    status, rows = tools.rest(run.cfg, run.key, 'GET', path)
    if status != 200:
        raise Blocked(f'{path} 읽기 {status}')
    return rows


def _patch(run, path, body):
    status, got = tools.rest(run.cfg, run.key, 'PATCH', path, body)
    if status >= 300:
        raise Blocked(f'{path} 바꾸기 {status} {got}')


def _otp(run, email):
    """앱과 같은 가입 요청(공개 키, 새 사용자 만들기 켬)."""
    return tools.call('POST', f"{run.cfg['SUPABASE_URL']}/auth/v1/otp", {'apikey': run.cfg['SUPABASE_ANON_KEY']},
                      {'email': email, 'create_user': True})


def _find_user(run, email):
    return next((u for u in tools.auth_users(run.cfg, run.key) if (u.get('email') or '').lower() == email.lower()), None)


def _test_university(run):
    rows = _rows(run, f'university_email_domains?domain=eq.{tools.mail_base(run.cfg)[1]}&select=university_id')
    return rows[0]['university_id'] if rows else None


def _signed_up(run, n, email, check):
    """가입 요청으로 생긴 계정을 찾아 accounts.json 에 적는다(뒷정리 대상)."""
    user = _find_user(run, email)
    check.that(user is not None, 'auth 사용자 0명')
    if user:
        run.remember({'n': n, 'email': email, 'id': user['id'], 'stage': 'new',
                      'at': datetime.now(timezone.utc).isoformat(timespec='seconds')})
    return user


def _no_user(run, email, check):
    """거절돼야 할 주소로 계정이 생겼으면 바로 지운다 — example.com 은 뒷정리 정규식 밖이라 남으면 안 지워진다."""
    user = _find_user(run, email)
    if not user:
        return
    kept = tools.keep(run.out.parent)
    if user['id'] in kept:  # 번호표가 지워져 별칭이 겹친 경우 — 그래도 KEEP 은 안 지운다
        check.problems.append(f"계정이 있다({user['id']}) — KEEP 이라 안 지움")
        return
    tools.delete_user(run.cfg, run.key, user['id'], kept)
    check.problems.append(f"계정이 만들어졌다({user['id']}) — 바로 지움")


def auth_01(run):
    check = Check()
    n, email = run.alias()
    check.reply('가입 요청', _otp(run, email), 200)
    if user := _signed_up(run, n, email, check):
        rows = _rows(run, f"profiles?id=eq.{user['id']}&select=status,student_verification,university_id,referral_code")
        check.that(len(rows) == 1, f'profiles {len(rows)}행')
        for p in rows[:1]:
            check.that(p['status'] == 'pending', f"status {p['status']}")
            check.that(p['student_verification'] == 'none', f"student_verification {p['student_verification']}")
            check.that(p['university_id'] == _test_university(run), f"university_id {p['university_id']}")
            check.that(re.fullmatch(r'[A-HJ-NP-Z2-9]{6}', p['referral_code'] or ''), f"referral_code {p['referral_code']!r}")
    return check.result()


def auth_02(run):
    check = Check()
    n, email = run.alias(tools.mail_base(run.cfg)[1].upper())
    check.reply('대문자 도메인 가입', _otp(run, email), 200)
    if user := _signed_up(run, n, email, check):
        rows = _rows(run, f"profiles?id=eq.{user['id']}&select=university_id")
        check.that(len(rows) == 1 and rows[0]['university_id'] == _test_university(run), f'profiles {rows}')
    return check.result()


def _rejected(run, domain):
    check = Check()
    _, email = run.alias(domain)
    check.reply('가입 요청', _otp(run, email), 422, REJECTED)
    _no_user(run, email, check)
    return check.result()


def auth_03(run):
    return _rejected(run, 'example.com')


def auth_04(run):
    return _rejected(run, f"mail.{tools.mail_base(run.cfg)[1]}")


def auth_06(run):
    check = Check()
    url, body = f"{run.cfg['API_BASE_URL']}/hooks/before-user-created", {'user': {'email': 'e2e@example.com'}}
    check.reply('서명 없음', tools.call('POST', url, None, body), 401, 'invalid signature')
    forged = {'webhook-id': f'msg_{uuid.uuid4().hex}', 'webhook-timestamp': str(int(time.time())),
              'webhook-signature': 'v1,' + base64.b64encode(bytes(32)).decode()}
    check.reply('틀린 서명', tools.call('POST', url, forged, body), 401, 'invalid signature')
    return check.result()


def auth_13(run):
    """관리자 생성이 가입 훅을 타는지 모른다(T1) — 막혔다면 누가 막았는지 메모에 남긴다."""
    check = Check()
    _, email = run.alias('example.com')
    status, body = tools.admin(run.cfg, run.key, 'POST', 'users', {'email': email, 'email_confirm': True})
    check.that(status >= 400, f'관리자 생성이 {status} 로 성공')
    _no_user(run, email, check)
    return check.result('가입 훅이 막음' if REJECTED in str(_detail(body)) else '트리거가 막음')


def gate_06(run):
    check = Check()
    account = run.account('gate_done')
    _patch(run, f"profiles?id=eq.{account['id']}", {'status': 'suspended'})
    cards = _api(run, 'GET', '/cards/today', account['token'])
    check.reply('카드', cards, 403, '이용이 제한된 계정이에요')
    check.that(cards.headers.get('x-account-status') == 'suspended', f"X-Account-Status {cards.headers.get('x-account-status')}")
    check.reply('인증 상태', _api(run, 'GET', '/me/verification-status', account['token']), 200)
    return check.result()


def gate_15(run):
    check = Check()
    account = run.account('new')
    check.reply('필수 하나', _api(run, 'POST', '/me/consents', account['token'], {'agreed': ['terms']}), 400,
                '필수 항목에 모두 동의해 주세요')
    check.reply('안 받는 항목', _api(run, 'POST', '/me/consents', account['token'],
                                    {'agreed': ['terms', 'privacy', 'sensitive_religion']}), 422)
    rows = _rows(run, f"user_consents?profile_id=eq.{account['id']}&select=kind")
    check.that(not rows, f'user_consents {len(rows)}행')
    return check.result()


def _form(run, path, token, fields, file):
    """multipart 한 번 — [file] = (칸 이름, 파일 이름, 바이트)."""
    boundary = uuid.uuid4().hex
    parts = [f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode() for k, v in fields.items()]
    name, filename, data = file
    parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"; filename="{filename}"\r\n'
                 f'Content-Type: image/jpeg\r\n\r\n'.encode() + data + f'\r\n--{boundary}--\r\n'.encode())
    return tools.call('POST', f"{run.cfg['API_BASE_URL']}{path}", {'Authorization': f'Bearer {token}'},
                      raw=(b''.join(parts), f'multipart/form-data; boundary={boundary}'))


def gate_16(run):
    check = Check()
    account = run.account('new')
    reply = _form(run, '/student-verification', account['token'], {'real_name': '홍길동'}, ('photo', 'id.jpg', TINY_JPEG))
    check.reply('학생증 제출', reply, 403, CONSENT_REQUIRED)
    check.that('x-account-status' not in reply.headers, f"X-Account-Status {reply.headers.get('x-account-status')}")
    files = list(tools.storage_paths(run.cfg, run.key, 'student-id-temp', account['id']))
    check.that(not files, f'student-id-temp 파일 {len(files)}개')
    rows = _rows(run, f"student_verification_attempts?profile_id=eq.{account['id']}&select=id")
    check.that(not rows, f'attempts {len(rows)}행')
    return check.result()


def gate_20(run):
    """E-GATE-17 계정(온보딩 끝, 옛 판 동의만)은 홈 계정이라 묶음 2다 — 학과까지 마친 계정으로 대신한다.
    user_consents 는 고치지 않는 기록이라 서비스 키도 update 권한이 없다(20260929010000:22-23).
    그래서 판을 바꾸지 않고 옛 판 행을 처음부터 넣는다. /school-info 는 동의를 안 보므로(get_caller) 그다음에 학과를 넣는다."""
    check = Check()
    account = run.account('new')
    status, body = tools.rest(run.cfg, run.key, 'POST', 'user_consents',
                              [{'profile_id': account['id'], 'kind': k, 'version': '2026-09-01'} for k in ('privacy', 'terms')])
    if status >= 300:
        raise Blocked(f'옛 판 동의 넣기 {status} {body}')
    _patch(run, f"profiles?id=eq.{account['id']}", {'student_verification': 'verified'})
    reply = _api(run, 'POST', '/school-info', account['token'],
                 {'department': '컴퓨터공학과', 'student_number': f"e2e{account['n']}"})
    if reply[0] >= 300:
        raise Blocked(f'학과 저장 {reply[0]} {reply[1]}')
    check.reply('다음 단계', _api(run, 'GET', '/profile-onboarding/next-step', account['token']), 403, CONSENT_REQUIRED)
    check.reply('카드', _api(run, 'GET', '/cards/today', account['token']), 200)
    return check.result()


def gate_50(run):
    check = Check()
    for label, stage in (('none', 'consented'), ('pending', 'pending')):
        account = run.account(stage)
        for path in ('/cards/today', '/home/summary', '/profile-onboarding/next-step'):
            check.reply(f'{label} {path}', _api(run, 'GET', path, account['token']), 403, SV_REQUIRED)
        token = f"e2e-fake-{account['n']}"
        try:
            reply = _api(run, 'POST', '/cards/push-tokens', account['token'], {'token': token, 'platform': 'android'})
            check.reply(f'{label} 알림 토큰', reply, 200)
            check.that(reply[1] == {'ok': True}, f'{label} 알림 토큰 본문 {reply[1]}')
        finally:
            # FCM 400 은 죽은 토큰으로 안 쳐서 남는다 — 가짜 토큰은 바로 지운다.
            _api(run, 'DELETE', f'/cards/push-tokens/{token}', account['token'])
    return check.result()


def gate_51(run):
    check = Check()
    account = run.account('consented')
    check.reply('학과 저장', _api(run, 'POST', '/school-info', account['token'],
                                {'department': '컴퓨터공학과', 'student_number': f"e2e{account['n']}"}), 403, SV_REQUIRED)
    rows = _rows(run, f"profiles?id=eq.{account['id']}&select=major")
    check.that(rows and rows[0]['major'] is None, f'major {rows}')
    return check.result()


def gate_55(run):
    check = Check()
    account = run.account('verified')
    check.reply('카드', _api(run, 'GET', '/cards/today', account['token']), 403, '학과 정보를 먼저 입력해 주세요')
    return check.result()


def onb_08(run):
    check = Check()
    account = run.account('gate_done')
    year = datetime.now(SEOUL).year
    check.reply('너무 어림', _api(run, 'POST', '/profile-onboarding/basic-info', account['token'],
                                {**tools.basic_info(), 'birth_year': year - 18}), 422, contains=f'{year - 19}년생부터 가입할 수 있어요')
    check.reply('1949', _api(run, 'POST', '/profile-onboarding/basic-info', account['token'],
                            {**tools.basic_info(), 'birth_year': 1949}), 422, INVALID_INPUT)
    rows = _rows(run, f"profiles?id=eq.{account['id']}&select=nickname")
    check.that(rows and rows[0]['nickname'] is None, f'nickname {rows}')
    return check.result()


def onb_14(run):
    """번호는 암호문으로 저장된다(사용자 결정 8) — 평문 '+8210…' 대신 '암호문이 채워졌다' 를 본다."""
    check = Check()
    account = run.account('gate_done')
    check.reply('유선 번호', _api(run, 'POST', '/profile-onboarding/basic-info', account['token'],
                                {**tools.basic_info(), 'phone_number': '02-123-4567'}), 400, '전화번호를 다시 확인해 주세요')
    phone = tools.basic_info()['phone_number'].replace('010-', '+82 10-')
    check.reply('+82 번호', _api(run, 'POST', '/profile-onboarding/basic-info', account['token'],
                               {**tools.basic_info(), 'phone_number': phone}), 200)
    rows = _rows(run, f"profile_private?profile_id=eq.{account['id']}&select=phone_number")
    stored = rows[0]['phone_number'] if rows else None
    check.that(stored and '+8210' not in str(stored), f'phone_number {stored!r}')
    return check.result()


def onb_29(run):
    check = Check()
    account = run.account('basic')
    trials = ((['없는태그', '카페가기', '자전거'], '목록에 없는 태그'),
              (['카페가기', '카페가기', '자전거'], '같은 태그를 두 번 고를 수 없어요'),
              (['카페가기', '자전거'], '최소 3개를 골라야 해요'),
              (['카페가기', '자전거', '패션', '반려동물', '술', '산책'], '최대 5개까지 고를 수 있어요'))
    for tags, message in trials:
        check.reply(f'태그 {len(tags)}개', _api(run, 'POST', '/profile-onboarding/interests', account['token'], {'tags': tags}),
                    422, contains=message)
    rows = _rows(run, f"profiles?id=eq.{account['id']}&select=interest_tags")
    check.that(rows and not rows[0]['interest_tags'], f'interest_tags {rows}')
    return check.result()


def onb_32(run):
    """매번 바로 행 수를 본다 — 답을 먼저 넣고 종교를 나중에 저장하면 마지막 줄에서 행이 남는다."""
    check = Check()
    account = run.account('basic')
    answers = {str(axis): 0.5 for axis in range(1, 10)}
    trials = (('값 0.3', {**answers, '1': 0.3}, 'none'), ('축 10', {**answers, '10': 0.5}, 'none'), ('없는 종교', answers, 'jedi'))
    for label, given, religion in trials:
        check.reply(label, _api(run, 'POST', '/profile-onboarding/survey', account['token'],
                                {'answers': given, 'religion': religion, 'is_smoker': False}), 422, INVALID_INPUT)
        rows = _rows(run, f"survey_answers?profile_id=eq.{account['id']}&select=axis")
        check.that(not rows, f'{label} 뒤 survey_answers {len(rows)}행')
    return check.result()


def onb_45(run):
    check = Check()
    account = run.account('basic')
    base = {'preferred_age_min': 20, 'preferred_age_max': 30, 'preferred_animal_types': ['dog'], 'preferred_impression_types': ['kind']}
    trials = (('나이 거꾸로', {**base, 'preferred_age_min': 30, 'preferred_age_max': 20}, INVALID_INPUT),
              ('얼굴상 4개', {**base, 'preferred_animal_types': ['dog', 'cat', 'fox', 'bear']}, None),
              ('얼굴상 0개', {**base, 'preferred_animal_types': []}, None))
    for label, body, detail in trials:
        check.reply(label, _api(run, 'POST', '/profile-onboarding/ideal-conditions', account['token'], body), 422, detail)
    rows = _rows(run, f"profiles?id=eq.{account['id']}&select=preferred_age_min")
    check.that(rows and rows[0]['preferred_age_min'] is None, f'preferred_age_min {rows}')
    return check.result()


def onb_69(run):
    check = Check()
    account = run.account('pending')
    check.reply('추천 코드', _api(run, 'POST', '/referral/redeem', account['token'], {'code': 'ABCDEF'}), 403, SV_REQUIRED)
    return check.result()


CASES = {
    'E-AUTH-01': auth_01, 'E-AUTH-02': auth_02, 'E-AUTH-03': auth_03, 'E-AUTH-04': auth_04, 'E-AUTH-06': auth_06,
    'E-AUTH-13': auth_13, 'E-GATE-06': gate_06, 'E-GATE-15': gate_15, 'E-GATE-16': gate_16, 'E-GATE-20': gate_20,
    'E-GATE-50': gate_50, 'E-GATE-51': gate_51, 'E-GATE-55': gate_55, 'E-ONB-08': onb_08, 'E-ONB-14': onb_14,
    'E-ONB-29': onb_29, 'E-ONB-32': onb_32, 'E-ONB-45': onb_45, 'E-ONB-69': onb_69,
}
BUNDLES = {'area1-b1': list(CASES)}


def attempt(run, case):
    """가설 하나. 준비가 안 되면 blocked."""
    try:
        return CASES[case](run)
    except Blocked as e:
        return 'blocked', str(e)
