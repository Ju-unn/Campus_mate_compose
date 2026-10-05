"""영역 1 묶음 2 — 홈 계정 · 탈퇴 · 정리 배치 · 재동의 · 온보딩 뒷단(04-4 ~ 06-3) · 추천 코드(20 · 20d · 06-4).
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 1 의 그 줄이다. 앱 쪽은 frontend/integration_test/area1_b2.dart 의 같은 번호.

폰 가설은 area1.PHONE, API 가설은 area1.CASES 에 더해 `python -m e2e run area1-b2` 한 번으로 돈다.
"""

import calendar
import random
import time
import urllib.parse
from datetime import datetime, timedelta, timezone

from e2e import area1, area1_b3, batch_gate, notify, tools
from e2e.area1 import (CONSENT_VERSION, Check, _api, _app, _at, _detail, _find_user, _one, _otp, _patch, _rows,
                       _signed_in, _signed_up)
from e2e.tools import Blocked

# 시나리오에 있지만 이 묶음에 안 넣은 것.
LEFT_OUT = {
    'E-AUTH-15': '실제 Gmail 6자리 코드 · 5분 만료 — 대장이 손으로',
    'E-ONB-32': '묶음 1 API(area1-b1) 에 이미 있다(D-01)',
    'E-ONB-45': '묶음 1 API(area1-b1) 에 이미 있다',
    'E-ONB-69': '묶음 1 API(area1-b1) 에 이미 있다',
}

# 계정 단계(여기까지 끝냄) → 앱이 다시 켜졌을 때 가야 할 화면(앱 쪽 `screens` 의 키).
SCREEN_AFTER = {
    'gate_done': '04-1', 'basic': '04-1b', 'kakao': '04-2', 'photos': '04-4', 'appearance': '04-5', 'interests': '04-6',
    'my_traits': '05-01', 'survey': '05-12', 'avatar': '06-1', 'ideal_conditions': '06-2', 'ideal_traits': '06-2a',
    'ideal_note': '06-3', 'home': 'home',
}
REJOIN_BLOCKED = '재가입이 제한된 이메일이에요'
NOT_FOUND = '없는 코드예요, 다시 확인해 주세요'
NOT_ALLOWED = '이 코드는 쓸 수 없어요'
ONCE = '추천 코드는 한 번만 입력할 수 있어요'
CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'  # profiles_referral_code_format


def _blocks(run):
    return {r['email_hmac']: r for r in _rows(run, 'signup_blocks?select=email_hmac,blocked_until')}


def _new_block(run, before):
    """[before] 뒤에 생긴 재가입 제한 행 — HMAC 키 없이 어느 행이 이 계정 것인지 가른다(시험 중엔 실사용자가 없다)."""
    added = [row for key, row in _blocks(run).items() if key not in before]
    return added[0] if len(added) == 1 else None, len(added)


def _two_months_after(moment):
    month = moment.month + 2
    year, month = moment.year + (month - 1) // 12, (month - 1) % 12 + 1
    # Postgres interval '2 months' 처럼 그 달에 없는 날은 말일로 깎는다
    return moment.replace(year=year, month=month, day=min(moment.day, calendar.monthrange(year, month)[1]))


def _status(run, account_id):
    return _one(run, f'profiles?id=eq.{account_id}&select=status').get('status')


def _withdraw(run, account):
    reply = _api(run, 'POST', '/account/withdraw', account['token'])
    if reply[0] >= 300:
        raise Blocked(f'탈퇴 {reply[0]} {_detail(reply[1])}')


def _code(run, account_id):
    code = _one(run, f'profiles?id=eq.{account_id}&select=referral_code').get('referral_code')
    if not code:
        raise Blocked('추천 코드를 못 읽음')
    return code


def _hearts(run, account_id):
    return _rows(run, f'heart_transactions?profile_id=eq.{account_id}&reason=eq.referral&select=amount')


# ── 탈퇴 · 재가입 제한 ─────────────────────────────────────────────────────────────────────────────


def p_auth_07(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    before = _blocks(run)
    said = _app(check, phone(token_hash=token))
    block, added = _new_block(run, before)
    check.that(block is not None, f'새 재가입 제한 {added}행')
    if block and said.get('tapped_at'):
        expected = _two_months_after(_at(said['tapped_at']))
        gap = abs((_at(block['blocked_until']) - expected).total_seconds())
        check.that(gap <= 60, f"blocked_until {block['blocked_until']} — 누른 시각 + 2개월과 {gap:.0f}초 차이")
    check.that(_status(run, account['id']) == 'withdrawn', 'status 가 withdrawn 이 아님')
    return check.result()


def p_auth_08(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    _patch(run, f"profiles?id=eq.{account['id']}", {'status': 'suspended'})
    before = _blocks(run)
    _app(check, phone(token_hash=token))
    block, added = _new_block(run, before)
    check.that(block is not None and block['blocked_until'] == 'infinity', f'새 재가입 제한 {added}행 {block}')
    check.that(_status(run, account['id']) == 'withdrawn', 'status 가 withdrawn 이 아님')
    return check.result()


def p_auth_09(run, phone):
    check = Check()
    account = run.account('home')
    _withdraw(run, account)
    _app(check, phone(token_hash=run.link(account['email'])))  # 탈퇴 뒤에도 30일은 auth 사용자가 있다 — 새 로그인
    return check.result()


def _withdrawn_and_cleaned(run):
    """홈 계정을 탈퇴시키고 탈퇴 시각을 31일 전으로 돌려 정리 배치를 돌린다 → auth 사용자가 사라질 때까지 기다린다."""
    account = run.account('home')
    before = _blocks(run)
    _withdraw(run, account)
    block, added = _new_block(run, before)
    long_ago = (datetime.now(timezone.utc) - timedelta(days=31)).isoformat()
    _patch(run, f"profiles?id=eq.{account['id']}", {'withdrawn_at': long_ago})
    batch_gate.check('cleanup')
    tools.batch('cleanup')
    for _ in range(24):  # 2분
        if _find_user(run, account['email']) is None:
            return account, block
        time.sleep(5)
    raise Blocked('정리 배치 뒤 2분이 지나도 auth 사용자가 남아 있음')


def auth_10(run):
    check = Check()
    account, _ = _withdrawn_and_cleaned(run)
    check.reply('같은 메일 재가입', _otp(run, account['email']), 422, REJOIN_BLOCKED)
    check.that(_find_user(run, account['email']) is None, '거절됐어야 할 가입으로 auth 사용자가 생김')
    return check.result()


def auth_11(run):
    check = Check()
    account, block = _withdrawn_and_cleaned(run)
    if block is None:
        raise Blocked('탈퇴로 생긴 재가입 제한 행을 못 찾음')
    yesterday = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()
    _patch(run, f"signup_blocks?email_hmac=eq.{urllib.parse.quote(block['email_hmac'])}", {'blocked_until': yesterday})
    check.reply('같은 메일 재가입', _otp(run, account['email']), 200)
    if user := _signed_up(run, account['n'], account['email'], check):
        check.that(user['id'] != account['id'], '이전과 같은 id')
        check.that(len(_rows(run, f"profiles?id=eq.{user['id']}&select=id")) == 1, '새 profiles 행 없음')
    return check.result()


def auth_12(run):
    """만든 두 행은 시험 것 — 무기한 행은 끝에 지운다(시작 스냅샷 밖이라 cleanup 도 지우지만 바로)."""
    check = Check()
    expired, forever = (f'\\x{random.getrandbits(256):064x}' for _ in range(2))
    both = 'signup_blocks?email_hmac=' + urllib.parse.quote(f'in.({expired},{forever})', safe='')
    status, body = tools.rest(run.cfg, run.key, 'POST', 'signup_blocks', [
        {'email_hmac': expired, 'blocked_until': (datetime.now(timezone.utc) - timedelta(days=1)).isoformat(), 'key_version': 1},
        {'email_hmac': forever, 'blocked_until': 'infinity', 'key_version': 1}])
    if status >= 300:
        raise Blocked(f'제한 행 넣기 {status} {body}')
    try:
        batch_gate.check('cleanup')
        tools.batch('cleanup')
        rows = []
        for _ in range(24):
            rows = _rows(run, f'{both}&select=blocked_until')
            if len(rows) < 2:
                break
            time.sleep(5)
        check.that([r['blocked_until'] for r in rows] == ['infinity'], f'정리 뒤 남은 행 {rows}')
    finally:
        tools.rest(run.cfg, run.key, 'DELETE', both)
    return check.result()


# ── 정지 · 재동의 ─────────────────────────────────────────────────────────────────────────────────


def p_gate_04(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    _app(check, phone(token_hash=token, midway=lambda said: _patch(run, f"profiles?id=eq.{account['id']}", {'status': 'suspended'})))
    return check.result()


def p_gate_05(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    _patch(run, f"profiles?id=eq.{account['id']}", {'status': 'suspended'})
    _app(check, phone(token_hash=token, expect='suspended'), '정지')
    _patch(run, f"profiles?id=eq.{account['id']}", {'status': 'active'})
    _app(check, phone(fresh=False, expect='home'), '정지 풂')
    return check.result()


def p_gate_17(run, phone):
    check = Check()
    account = run.account('home', old_consent=True)
    _app(check, phone(token_hash=run.link(account['email'])))
    return check.result()


def p_gate_18(run, phone):
    check = Check()
    account = run.account('home', old_consent=True)
    _app(check, phone(token_hash=run.link(account['email'])))
    rows = _rows(run, f"user_consents?profile_id=eq.{account['id']}&select=kind,version")
    now = sorted(r['kind'] for r in rows if r['version'] == CONSENT_VERSION)
    check.that(now == ['privacy', 'terms'], f'새 판 동의 {now}')
    return check.result()


def p_gate_19(run, phone):
    check = Check()
    account = run.account('home', old_consent=True)
    on = tools.call('POST', f"{run.cfg['SUPABASE_URL']}/rest/v1/notification_settings?on_conflict=profile_id",
                    {'apikey': run.key, 'Authorization': f'Bearer {run.key}', 'Prefer': 'resolution=merge-duplicates'},
                    {'profile_id': account['id'], 'marketing': True})
    if on[0] >= 300:
        raise Blocked(f'마케팅 켜 두기 {on[0]} {on[1]}')
    _app(check, phone(token_hash=run.link(account['email'])))
    settings = _one(run, f"notification_settings?profile_id=eq.{account['id']}&select=marketing")
    check.that(settings.get('marketing') is True, f'marketing {settings}')
    return check.result()


# ── 온보딩 뒷단(04-4 ~ 06-3) ──────────────────────────────────────────────────────────────────────


def _at_stage(stage, **job):
    """[stage] 까지 API 로 채운 계정으로 앱을 켠다 — 판정은 앱이 다 한다."""
    def case(run, phone):
        check = Check()
        _, token = _signed_in(run, stage)
        _app(check, phone(token_hash=token, **job))
        return check.result()
    return case


def p_onb_28(run, phone):
    """관심사(04-5) · 나의 특징(04-6) · 이상형 특징(06-2) 세 화면 — 계정 셋."""
    check = Check()
    for stage, screen in (('appearance', '04-5'), ('interests', '04-6'), ('ideal_conditions', '06-2')):
        _, token = _signed_in(run, stage)
        _app(check, phone(token_hash=token, expect=screen), screen)
    return check.result()


def p_onb_30(run, phone):
    check = Check()
    account, token = _signed_in(run, 'my_traits')
    _app(check, phone(token_hash=token))
    answers = _rows(run, f"survey_answers?profile_id=eq.{account['id']}&select=axis,value")
    check.that(sorted(a['axis'] for a in answers) == list(range(1, 10)), f'survey_answers 축 {sorted(a["axis"] for a in answers)}')
    check.that(all(float(a['value']) in (-1, -0.5, 0, 0.5, 1) for a in answers), f'값 {[a["value"] for a in answers]}')
    profile = _one(run, f"profiles?id=eq.{account['id']}&select=religion,is_smoker")
    check.that(profile.get('religion') is not None and profile.get('is_smoker') is not None, f'종교 · 흡연 {profile}')
    return check.result()


def p_onb_31(run, phone):
    check = Check()
    account, token = _signed_in(run, 'my_traits')
    _app(check, phone(token_hash=token), '5문항 답')
    _app(check, phone(fresh=False, expect='05-01'), '다시 켬')
    rows = _rows(run, f"survey_answers?profile_id=eq.{account['id']}&select=axis")
    check.that(not rows, f'survey_answers {len(rows)}행')
    return check.result()


def p_onb_33(run, phone):
    """05-12 는 완성 행이 없거나 만드는 중일 때 보인다 — 만드는 중 행으로 켜서, 앱이 멈춘 사이 PC 가 ready 로 바꿔 '완성됐어요' 로 바뀌게 한다."""
    check = Check()
    account, token = _signed_in(run, 'survey')
    # 행이 없으면 화면이 실패로 굳어 다시 안 묻는다 — 만드는 중(pending) 행을 먼저 둬 5초 폴링을 살려 둔다
    status, body = run._avatar(account, 'pending')
    if status >= 300:
        raise Blocked(f'아바타 만드는 중 행 넣기 {status} {body}')

    def finish(said):
        _patch(run, f"profile_avatars?profile_id=eq.{account['id']}", {'status': 'ready'})
    _app(check, phone(token_hash=token, midway=finish))
    return check.result()


def p_onb_44(run, phone):
    check = Check()
    account, token = _signed_in(run, 'avatar')
    _app(check, phone(token_hash=token))
    saved = _one(run, f"profiles?id=eq.{account['id']}&select=preferred_age_min,preferred_age_max,preferred_height_min,preferred_height_max")
    check.that((saved.get('preferred_age_min'), saved.get('preferred_age_max')) == (19, 35), f'나이 {saved}')
    check.that(saved.get('preferred_height_min') is None and saved.get('preferred_height_max') is None, f'키 {saved}')
    return check.result()


def _note_saved(run, phone):
    """앱이 막힌 값은 저장 0, 받은 값(said['saved'])은 그대로 저장됐는지."""
    check = Check()
    account, token = _signed_in(run, 'ideal_traits')
    said = _app(check, phone(token_hash=token))
    saved = _one(run, f"profiles?id=eq.{account['id']}&select=ideal_note").get('ideal_note')
    check.that(saved is not None and saved == said.get('saved', '').strip(), f'ideal_note {saved!r}(앱 {said.get("saved")!r})')
    return check.result()


def p_onb_48(run, phone):
    check = Check()
    account, token = _signed_in(run, 'ideal_note')
    said = _app(check, phone(token_hash=token))
    saved = _one(run, f"profiles?id=eq.{account['id']}&select=bio_draft")
    check.that(saved.get('bio_draft') and saved['bio_draft'] == said.get('draft'), f"bio_draft {saved.get('bio_draft')!r}(앱 {said.get('draft')!r})")
    return check.result()


def p_onb_50(run, phone):
    check = Check()
    account, token = _signed_in(run, 'ideal_note')
    said = _app(check, phone(token_hash=token), '첫 초안')
    first = _one(run, f"profiles?id=eq.{account['id']}&select=bio_draft,bio_draft_generated_at")
    _app(check, phone(fresh=False, draft=said.get('draft')), '다시 켬')
    again = _one(run, f"profiles?id=eq.{account['id']}&select=bio_draft,bio_draft_generated_at")
    check.that(again == first, f'초안이 바뀜 {first} → {again}')
    return check.result()


def p_onb_52(run, phone):
    check = Check()
    account, token = _signed_in(run, 'ideal_note')
    _app(check, phone(token_hash=token))
    check.that(_status(run, account['id']) == 'active', 'status 가 active 가 아님')
    step = _api(run, 'GET', '/profile-onboarding/next-step', account['token'])
    check.that(step[0] == 200 and (step[1] or {}).get('step') == 'complete', f'next-step {step[1]}')
    return check.result()


def p_onb_53(run, phone):
    """시나리오는 기기 둘 — A폰 한 대로 13계정(basic_info ~ bio 12 + complete)."""
    check = Check()
    for stage, screen in SCREEN_AFTER.items():
        _, token = _signed_in(run, stage)
        _app(check, phone(token_hash=token, expect=screen), stage)
    return check.result()


def p_onb_54(run, phone):
    check = Check()
    _, token = _signed_in(run, 'photos')
    _app(check, phone(token_hash=token), '04-4 저장')
    _app(check, phone(fresh=False, expect='04-5'), '다시 켬')
    return check.result()


def p_onb_55(run, phone):
    """얼굴 검사를 거치는 04-2 라 진짜 얼굴 사진(묶음 3 의 사진 세트 face1~3)을 폰에 넣어 고르게 한다. 세트가 없으면 계정 전에 blocked."""
    check = Check()
    names = ['face1.jpg', 'face2.jpg', 'face3.jpg']
    area1_b3._photos(run, *names)
    account, token = _signed_in(run, 'kakao')
    area1_b3._push(phone, run, *names)
    _app(check, phone(token_hash=token, photos=names), '사진 3장 고름')
    _app(check, phone(fresh=False, expect='04-2'), '다시 켬')
    rows = _rows(run, f"profile_photos?profile_id=eq.{account['id']}&select=id")
    check.that(not rows, f'profile_photos {len(rows)}행')
    return check.result()


# ── 추천 코드(20) · 유입경로(20d) · 지인 차단(06-4) ──────────────────────────────────────────────


def _referrer(run, **basic):
    account = run.account('home', **basic)
    return account, _code(run, account['id'])


def _unused_code(run):
    for _ in range(20):
        code = ''.join(random.choices(CODE_CHARS, k=6))
        if not _rows(run, f'profiles?referral_code=eq.{code}&select=id'):
            return code
    raise Blocked('안 쓰인 코드를 못 만듦')


def _referred(run, phone, code_for_app=lambda code: code):
    """B(추천인) 와 A(06-3 직전) — 앱이 A 로 자기소개를 내고 20 에서 B 코드를 넣는다."""
    check = Check()
    b, code = _referrer(run)
    a, token = _signed_in(run, 'ideal_note')
    _app(check, phone(token_hash=token, code=code_for_app(code)))
    rows = _rows(run, f"referrals?referee_id=eq.{a['id']}&select=referrer_id")
    check.that(rows == [{'referrer_id': b['id']}], f'referrals {rows}')
    for who, account in (('나', a), ('추천인', b)):
        got = [h['amount'] for h in _hearts(run, account['id'])]
        check.that(got == [50], f'{who} 하트 {got}')
    return check.result()


def p_onb_60(run, phone):
    return _referred(run, phone)


def p_onb_62(run, phone):
    return _referred(run, phone, lambda code: f' {code.lower()} ')


def _ours(dump):
    """dumpsys notification 에서 우리 앱 알림의 제목 · 본문 줄만 — 다른 앱의 알림은 원문이 개인 것이라 보지도 남기지도 않는다."""
    return [line.strip() for record in (dump or '').split('NotificationRecord(') if f'pkg={tools.PACKAGE}' in record
            for line in record.splitlines() if 'android.title' in line or 'android.text' in line]


def p_onb_61(run, phone):
    """추천인 = 폰 A(앱을 홈까지 켠 뒤 HOME 으로 내림), 코드 입력 = API(새 계정). 낮 08~22시에 돌린다."""
    notify.ensure_delivery(phone.serial)  # 푸시 연결이 죽은 폰이면 "알림이 안 왔다" 를 앱 탓으로 읽게 된다 — 시작 때 한 번 점검
    check = Check()
    b, token = _signed_in(run, 'home')
    _app(check, phone(token_hash=token))
    code = _code(run, b['id'])
    tools.adb(phone.serial, 'shell', 'input', 'keyevent', 'KEYCODE_HOME')
    a = run.account('ideal_note')
    nickname = _one(run, f"profiles?id=eq.{a['id']}&select=nickname").get('nickname') or ''
    check.reply('코드 입력', _api(run, 'POST', '/referral/redeem', a['token'], {'code': code}), 200)
    want = f'{nickname} 님이 가입했어요, 리뷰를 남겨 주세요'
    found = ''
    for _ in range(15):  # 30초
        found = ' / '.join(_ours(tools.adb(phone.serial, 'shell', 'dumpsys', 'notification', '--noredact', check=False)))
        if want in found:  # 제목만 보면 앞 시도의 옛 알림에서 끊긴다 — 이 시도의 닉네임이 든 본문까지
            break
        time.sleep(2)
    # 실폰 알림 원문은 저장하지 않는다(설계 2절) — 맞으면 메모 없이, 틀리면 우리 글자만 남긴다.
    check.that('친구가 가입했어요' in found, '30초 안에 "친구가 가입했어요" 알림 없음')
    check.that(want in found, f'본문이 다름 — 기대 "{want}", 우리 앱 알림 글자: {found}')
    return check.result()


def p_onb_64(run, phone):
    check = Check()
    a, token = _signed_in(run, 'ideal_note')
    _app(check, phone(token_hash=token, code=_unused_code(run)))
    check.that(not _hearts(run, a['id']), '없는 코드인데 하트가 생김')
    return check.result()


def p_onb_65(run, phone):
    check = Check()
    a, token = _signed_in(run, 'ideal_note')
    _app(check, phone(token_hash=token, code=_code(run, a['id'])))
    check.that(not _hearts(run, a['id']), '내 코드인데 하트가 생김')
    return check.result()


def p_onb_66(run, phone):
    check = Check()
    suspended, code1 = _referrer(run)
    _patch(run, f"profiles?id=eq.{suspended['id']}", {'status': 'suspended'})
    withdrawn, code2 = _referrer(run)
    _withdraw(run, withdrawn)
    a, token = _signed_in(run, 'ideal_note')
    _app(check, phone(token_hash=token, codes=[code1, code2]))
    check.that(not _hearts(run, a['id']), '하트가 생김')
    return check.result()


def onb_67(run):
    """두 경우 다 서버 판정(422)이라 API 로 — 같은 문구가 화면에 뜨는지는 E-ONB-65 가 본다."""
    check = Check()
    shared = f'010-{random.randint(1000, 9999)}-{random.randint(1000, 9999)}'
    b, code = _referrer(run, phone_number=shared)
    a = run.account('home', phone_number=shared)
    check.reply('추천인과 같은 번호', _api(run, 'POST', '/referral/redeem', a['token'], {'code': code}), 422, NOT_ALLOWED)
    other = f'010-{random.randint(1000, 9999)}-{random.randint(1000, 9999)}'
    b2, code2 = _referrer(run)
    c = run.account('home', phone_number=other)
    check.reply('C 가 먼저 사용', _api(run, 'POST', '/referral/redeem', c['token'], {'code': code2}), 200)
    a2 = run.account('home', phone_number=other)
    check.reply('C 와 같은 번호', _api(run, 'POST', '/referral/redeem', a2['token'], {'code': code2}), 422, NOT_ALLOWED)
    check.that(len(_rows(run, f"referrals?referrer_id=eq.{b2['id']}&select=referee_id")) == 1, '두 번째 추천인의 referrals 가 1행이 아님')
    check.that(not _rows(run, f"referrals?referrer_id=eq.{b['id']}&select=referee_id"), '첫 추천인의 referrals 가 생김')
    return check.result()


def onb_68(run):
    check = Check()
    a = run.account('home')
    _, code1 = _referrer(run)
    _, code2 = _referrer(run)
    check.reply('첫 코드', _api(run, 'POST', '/referral/redeem', a['token'], {'code': code1}), 200)
    check.reply('둘째 코드', _api(run, 'POST', '/referral/redeem', a['token'], {'code': code2}), 409, ONCE)
    got = [h['amount'] for h in _hearts(run, a['id'])]
    check.that(got == [50], f'하트 {got}')
    return check.result()


def p_onb_70(run, phone):
    check = Check()
    a, token = _signed_in(run, 'ideal_note')
    _app(check, phone(token_hash=token))
    check.that(not _rows(run, f"referrals?referee_id=eq.{a['id']}&select=referrer_id"), 'referrals 가 생김')
    saved = _one(run, f"profiles?id=eq.{a['id']}&select=acquisition_channel")
    check.that(saved.get('acquisition_channel') is None, f'acquisition_channel {saved}')
    check.that(not _rows(run, f"contact_blocks?owner_id=eq.{a['id']}&select=id"), 'contact_blocks 가 생김')
    return check.result()


def p_onb_71(run, phone):
    check = Check()
    _, token = _signed_in(run, 'ideal_note')
    _app(check, phone(token_hash=token), '20 도착')
    _app(check, phone(fresh=False, expect='home'), '다시 켬')
    return check.result()


def _acquisition(channel, note_length):
    def case(run, phone):
        check = Check()
        a, token = _signed_in(run, 'ideal_note')
        _app(check, phone(token_hash=token))
        saved = _one(run, f"profiles?id=eq.{a['id']}&select=acquisition_channel,acquisition_note")
        note = saved.get('acquisition_note')
        check.that(saved.get('acquisition_channel') == channel, f'acquisition_channel {saved}')
        check.that((len(note) if note else 0) == note_length, f'acquisition_note {note!r}')
        return check.result()
    return case


PHONE = {
    'E-AUTH-07': p_auth_07, 'E-AUTH-08': p_auth_08, 'E-AUTH-09': p_auth_09,
    'E-GATE-04': p_gate_04, 'E-GATE-05': p_gate_05,
    'E-GATE-17': p_gate_17, 'E-GATE-18': p_gate_18, 'E-GATE-19': p_gate_19,
    'E-ONB-27': _at_stage('photos'), 'E-ONB-28': p_onb_28, 'E-ONB-30': p_onb_30, 'E-ONB-31': p_onb_31,
    'E-ONB-33': p_onb_33, 'E-ONB-43': _at_stage('avatar'), 'E-ONB-44': p_onb_44,
    'E-ONB-46': _note_saved, 'E-ONB-47': _note_saved, 'E-ONB-48': p_onb_48, 'E-ONB-49': _at_stage('ideal_note'),
    'E-ONB-50': p_onb_50, 'E-ONB-51': _at_stage('ideal_note'), 'E-ONB-52': p_onb_52, 'E-ONB-53': p_onb_53,
    'E-ONB-54': p_onb_54, 'E-ONB-55': p_onb_55, 'E-ONB-56': _at_stage('appearance'),
    'E-ONB-60': p_onb_60, 'E-ONB-61': p_onb_61, 'E-ONB-62': p_onb_62, 'E-ONB-63': _at_stage('ideal_note'),
    'E-ONB-64': p_onb_64, 'E-ONB-65': p_onb_65, 'E-ONB-66': p_onb_66, 'E-ONB-70': p_onb_70, 'E-ONB-71': p_onb_71,
    'E-ONB-72': _acquisition('other', 30), 'E-ONB-73': _acquisition('everytime', 0),
}
CASES = {'E-AUTH-10': auth_10, 'E-AUTH-11': auth_11, 'E-AUTH-12': auth_12, 'E-ONB-67': onb_67, 'E-ONB-68': onb_68}

area1.PHONE.update(PHONE)
area1.CASES.update(CASES)
# E-GATE-03 은 묶음 1 함수가 홈 계정 칸까지 돈다(area1.p_gate_03) — 여기서 다시 돌린다.
area1.BUNDLES['area1-b2'] = list(CASES) + ['E-GATE-03'] + list(PHONE)
