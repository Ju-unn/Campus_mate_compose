"""영역 2 폰 A 3차 — 망 끊기 5 · 알림 2 · 카드 3 · 공유 창 1 · 하트 모자람 1(비AI 12개) + 실제 AI 3개(별도 묶음).
기대값은 시나리오 md 가 아니라 지금 코드 기준이다(앱 쪽은 frontend/integration_test/area2_c.dart 의 같은 번호).

`python -m e2e run area2-phone3` 로 12개, 실제 AI 는 `E2E_REAL_AI=1 python -m e2e run area2-phone3-ai`(OpenAI 이미지 호출 3건).
쓰기는 이번 실행이 만든 계정 id 와 시험 지역(`e2e`) 설정 행에만 — 지역 행은 바꾸기 전 값을 적어 두었다가 끝나면 되돌린다.
"""

import os
import re
import subprocess
import time
from contextlib import contextmanager
from datetime import datetime, timedelta

from e2e import area1, area2, area4_set2, notify, tools
from e2e.area1 import SEOUL, Check, _api, _app, _one, _patch, _rows, _signed_in
from e2e.area2 import _ONCE, _card, _grant, _guard, _insert, _person
from e2e.area4 import _cut, _offline, _restore, stepper
from e2e.tools import Blocked

WEEKDAY_NAMES = '월화수목금토일'  # frontend/lib/matching/view/daily_card_summary.dart weekdayNames
EVERY_DAY = [1, 2, 3, 4, 5, 6, 7]
TWICE_A_WEEK = [1, 4]
CARD_TITLE, CARD_BODY = '오늘의 카드가 도착했어요', '지금 확인해 보세요'  # issuing.py — 앱바 "오늘의 카드" 와는 별개
FRIEND_TITLE = '친구가 가입했어요'  # friend_reviews/router.py notify_review_request
LOW_HEARTS = '하트가 모자라요'  # errors.HEARTS_NOT_ENOUGH
AI_WAIT = 480  # 아바타 한 장이 완성되기를 기다리는 시간(초) — 시나리오 "수 분 안"
POLL = 5
TEST_REGION = 'e2e'  # region_group_settings 에서 쓰기를 허락하는 유일한 지역(시나리오 G1)
_PAID = {}  # 유료(AI) 호출이 이미 시작된 가설 → 그때까지 나온 (결과, 메모). run_case 의 fail 재시도로 같은 비용을 두 번 내지 않고, 다시 불리면 이 결과를 돌려준다
SHARE_LABELS = ['복사', 'Copy']
LADDER_ZERO = {'ladder_twice_per_week_min': 0, 'ladder_three_per_week_min': 0, 'ladder_four_per_week_min': 0,
               'ladder_daily_min': 0}  # 시나리오 G6 — 임계값 전부 0 이면 배치가 매일 지급으로 저장한다


# ── 순수 도우미 ─────────────────────────────────────────────────────────────────────────────────────

def now_seoul():
    return datetime.now(SEOUL)


def _hour_label(hour):
    """"오전 7시" — daily_card_summary.dart hourLabel 과 같다(분은 지급 시각이 늘 정시라 뺀다)."""
    return f"{'오전' if hour < 12 else '오후'} {hour % 12 or 12}시"


def expected_subtitle(now, weekdays, hour=7):
    """화면 11 의 부제 — 서버 next_issue_at(오늘 다음 첫 지급 요일, 내일부터 찾는다)과 앱 waitingSubtitle 을 그대로 옮겼다.
    [now] 는 서울 시각, [weekdays] 는 ISO 요일(1=월)."""
    ahead = next(n for n in range(1, 8) if (now + timedelta(days=n)).isoweekday() in weekdays)
    issue = now + timedelta(days=ahead)
    if ahead <= 1:
        return f'내일 {_hour_label(hour)}에 새로운 한 명이 도착해요'
    next_week = '다음 주 ' if ahead > 7 - now.isoweekday() else ''  # 주는 월요일 시작
    return f'{next_week}{WEEKDAY_NAMES[issue.weekday()]}요일 {_hour_label(hour)}에 새로운 사람을 찾아볼게요'


def real_ai_gate(env=None):
    """실제 AI(OpenAI 이미지 호출 = 비용) 가설은 E2E_REAL_AI=1 일 때만."""
    if (os.environ if env is None else env).get('E2E_REAL_AI') != '1':
        raise Blocked('실제 AI 호출(비용) — E2E_REAL_AI=1 일 때만 돈다')


def notice_memo(new, limit=5, width=80):
    """우리 앱의 새 알림 실제 "제목 / 본문" — 틀렸을 때 메모가 진단이 된다. 처음 [limit] 건만, 글은 repr(보이지 않는 글자까지)로 [width] 자까지.
    [new] 는 parse_notifications 가 우리 앱 것만 거른 목록이라 다른 앱 알림은 들어오지 않는다."""
    shown = ' · '.join(f'{n.title[:width]!r} / {n.text[:width]!r}' for n in new[:limit])
    return (shown + (f' 외 {len(new) - limit}건' if len(new) > limit else '')) or '없음'


def tap_point(xml, labels):
    """uiautomator 덤프에서 text 나 content-desc 가 [labels] 중 하나인 첫 노드의 가운데 (x, y). 없으면 None.
    덤프 원문은 저장하지 않는다 — 호출한 쪽이 좌표만 쓴다."""
    for node in re.findall(r'<node\b[^>]*>', xml or ''):
        words = {m.group(1) for m in re.finditer(r'(?<![\w-])(?:text|content-desc)="([^"]*)"', node)}
        box = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', node)
        if box and words & set(labels):
            x1, y1, x2, y2 = map(int, box.groups())
            return (x1 + x2) // 2, (y1 + y2) // 2
    return None


# ── 기기 · 서버 도우미 ───────────────────────────────────────────────────────────────────────────────

def offline(phone, check, *stages, **job):
    """area4._offline(망은 어떻게 끝나든 되돌린다) + 우편함 reverse 를 다시 건다 — 비행기 모드 뒤 USB 매핑이 풀린 기기 대비."""
    try:
        return _offline(phone, check, *stages, **job)
    finally:
        tools.adb(phone.serial, 'reverse', f'tcp:{tools.DEVICE_PORT}', f'tcp:{phone.hub.port}', check=False)


@contextmanager
def region_set(run, region, **fields):
    """시험 지역 설정 행의 [fields] 를 바꾸고, 끝나면(예외여도) 바꾸기 전 값으로 되돌린다. 실제 서울 지역은 안 쓴다."""
    if region != TEST_REGION:
        raise Blocked(f'시험 지역이 {region!r} — {TEST_REGION!r} 지역 설정만 바꾼다(시험대학을 {TEST_REGION} 지역으로 옮겨 둘 것)')
    where = f'region_group_settings?region_group=eq.{region}'
    row = _one(run, f"{where}&select={','.join(fields)}")
    if not row:
        raise Blocked(f'region_group_settings 에 {region!r} 행이 없음')
    before = {key: row[key] for key in fields}
    _patch(run, where, fields)
    try:
        yield
    finally:
        _patch(run, where, before)


def _region_of(run, account):
    return ((_one(run, f"profiles?id=eq.{account['id']}&select=universities(region_group)").get('universities')) or {}).get('region_group')


def _avatars(run, account):
    return _rows(run, f"profile_avatars?profile_id=eq.{account['id']}&select=id,status")


def _balance(run, account):
    rows = _rows(run, f"entitlements?profile_id=eq.{account['id']}&select=heart_balance")
    return rows[0]['heart_balance'] if rows else 0


def _add_avatar(run, account):
    """완성 아바타 한 장을 더 — 다시 만들기 값은 완성(ready) 수로 정해진다(avatar_regen_cost)."""
    _guard(run, account['id'])
    reply = run._avatar(account)
    if reply[0] >= 300:
        raise Blocked(f'아바타 행 넣기 {reply[0]} {reply[1]}')


def _give(run, account, amount):
    status, got = _grant(run, account, amount)
    if status >= 300:
        raise Blocked(f'하트 {amount} 넣기 {status} {got}')


def _slow(phone, timeout):
    """Phone 은 기다리는 시간을 못 받는다(Run.phone 기본 180초) — AI 는 Run.phone 을 직접 길게."""
    run = getattr(phone, 'run', None)
    if run is None:
        return phone
    return lambda midway=None, **job: run.phone(phone.hub, phone.serial, {'case': phone.case, **job}, timeout=timeout, midway=midway)


def _seed_pair(run):
    """A(남) · B(여) — 서로 후보인 한 쌍. A 로 로그인할 1회용 토큰까지."""
    a, b = _person(run, 'male'), _person(run, 'female')
    return a, b, run.link(a['email'])


# ── 망 끊기 5 ───────────────────────────────────────────────────────────────────────────────────────

def _cut_case(*restore):
    """홈에서 멈춘 사이 망을 끊고([restore] 가 있으면 앱이 오류를 본 뒤 다시 켠다) 앱이 판정한다."""
    def case(run, phone):
        check = Check()
        _, token = _signed_in(run, 'home')
        offline(phone, check, _cut(phone), *[_restore(phone) for _ in restore], token_hash=token)
        return check.result()
    return case


def p_ref_05(run, phone):
    """E-SET-61 과 같은 동작 — 앱은 그 가설을 별칭으로 쓴다(코드 · 오류 · 다시 시도)."""
    return area4_set2.p_set_61(run, phone)


# ── 카드 3 ──────────────────────────────────────────────────────────────────────────────────────────

def _waiting(weekdays):
    """오늘 몫을 끝낸 A(결정한 카드 하나, 후보 C 남음)의 오늘 탭 11 — 지급 요일을 [weekdays] 로 바꿔 부제를 본다."""
    def case(run, phone):
        check = Check()
        a, b = _person(run, 'male'), _person(run, 'female')
        _person(run, 'female')  # C — 아직 후보로 남는 사람
        decided = _card(run, a, b)
        check.reply('결정', _api(run, 'POST', f'/cards/{decided}/decision', a['token'], {'decision': 'reject'}), 200)
        region = _region_of(run, a)
        hour = int(((_one(run, f'region_group_settings?region_group=eq.{region}&select=issue_time') or {}).get('issue_time') or '07')[:2])
        with region_set(run, region, issue_weekdays=weekdays):
            today = now_seoul()
            _app(check, phone(token_hash=run.link(a['email']), subtitle=expected_subtitle(today, weekdays, hour)))
            if now_seoul().date() != today.date():
                raise Blocked('시험 중 자정을 넘겨 기대 부제를 못 믿는다')
        return check.result()
    return case


def p_card_35(run, phone):
    check = Check()
    a, b, token = _seed_pair(run)
    card = _card(run, a, b)

    def block(said):  # A 가 10b 를 연 채 B 가 A 를 차단한다
        _insert(run, 'blocks', [{'blocker_id': b['id'], 'blocked_id': a['id']}], a['id'], b['id'])

    _app(check, phone(midway=stepper(phone, block), token_hash=token))
    check.that(not _rows(run, f'card_decisions?card_id=eq.{card}&select=card_id'), 'card_decisions 에 행이 생김(차단된 카드의 수락이 저장됨)')
    return check.result()


# ── 알림 2 ──────────────────────────────────────────────────────────────────────────────────────────

def _dump(serial):
    return notify._ui_dump(serial)  # exec-out 으로 읽고 XML 이 아니면 Blocked — 읽는 길을 한 곳에 둔다


def _tap_label(serial, labels):
    point = tap_point(_dump(serial), labels)
    if point:
        tools.adb(serial, 'shell', 'input', 'tap', str(point[0]), str(point[1]))
    return point is not None


def _wait_for(until, seconds):
    deadline = time.monotonic() + seconds
    while not until():
        if time.monotonic() >= deadline:
            return False
        time.sleep(POLL)
    return True


def p_card_02(run, phone):
    """앱을 홈에서 멈추고 HOME → 카드 배치 → 알림 30초 → 알림을 눌러 오늘 탭으로. 앱이 그 카드를 판정한다."""
    notify.ensure_delivery(phone.serial)  # 푸시 연결이 죽은 폰이면 "알림이 안 왔다" 를 앱 탓으로 읽게 된다 — 시작 때 한 번 점검
    check = Check()
    a, b, token = _seed_pair(run)
    region = _region_of(run, a)
    target = _one(run, f"profiles?id=eq.{b['id']}&select=nickname,birth_year,universities(name)")
    shown = {'name_age': f"{target.get('nickname')}, {now_seoul().year - (target.get('birth_year') or 0) + 1}",  # 나이 = 올해 − 태어난 해 + 1
             'school': (target.get('universities') or {}).get('name') or ''}

    def background(said):
        # 기기 토큰이 서버에 올라와야 배치가 보낸 알림이 이 폰에 닿는다(E-SET-65 와 같은 기다림)
        if not _wait_for(lambda: _rows(run, f"push_tokens?profile_id=eq.{a['id']}&select=token"), 30):
            raise Blocked('30초 안에 기기 토큰이 서버에 안 올라옴 — 알림 권한 · FCM 확인')
        before = notify.read_notifications(phone.serial)  # 앞에 남은 알림과 섞이지 않게 — 새로 생긴 것만 본다
        notify.background(phone.serial)  # 앱이 앞에 있으면 배너가 안 뜬다(시나리오 G4)
        area2._batch('daily-cards')
        got = _wait_for(lambda: _rows(run, f"daily_cards?owner_id=eq.{a['id']}&source=eq.daily&select=id"), 90)
        check.that(got, '배치 뒤 90초 안에 A 의 daily_cards 가 안 생김')
        if not got:
            return
        new = notify.wait_new(phone.serial, before, seconds=30, match=lambda n: (n.title, n.text) == (CARD_TITLE, CARD_BODY))
        arrived = [n for n in new if (n.title, n.text) == (CARD_TITLE, CARD_BODY)]
        check.that(arrived, f'30초 안에 알림 "{CARD_TITLE} / {CARD_BODY}" 없음(새 알림 {len(new)}건: {notice_memo(new)})')
        if arrived:
            notify.tap_notification(phone.serial, CARD_TITLE)
            time.sleep(1)

    notify.grant_notifications(phone.serial)
    try:
        with region_set(run, region, issue_weekdays=EVERY_DAY, **LADDER_ZERO):
            _app(check, phone(midway=stepper(phone, background), token_hash=token, **shown))
    finally:
        notify.revoke_notifications(phone.serial)
    cards = _rows(run, f"daily_cards?owner_id=eq.{a['id']}&select=id,source")
    check.that(len(cards) == 1, f'A 카드가 {len(cards)}장(기대 1)')
    return check.result()


def p_ref_18(run, phone):
    """추천인 = 폰 A(홈까지 켠 뒤 HOME), 코드 입력 = API(새 계정). 낮 08~22시에만."""
    notify.require_daytime()
    notify.ensure_delivery(phone.serial)  # 푸시 연결이 죽은 폰이면 "알림이 안 왔다" 를 앱 탓으로 읽게 된다 — 시작 때 한 번 점검
    check = Check()
    referrer, token = _signed_in(run, 'home')
    _app(check, phone(token_hash=token))
    code = area4_set2._code(run, referrer['id'])
    # 기기 토큰이 서버에 올라와야 가입 알림이 이 폰에 닿는다 — 없으면 알림 시험이 아니라 준비 실패(p_card_02 와 같은 기다림)
    if not _wait_for(lambda: _rows(run, f"push_tokens?profile_id=eq.{referrer['id']}&select=token"), 30):
        raise Blocked('30초 안에 기기 토큰이 서버에 안 올라옴 — 알림 권한 · FCM 확인')
    before = notify.read_notifications(phone.serial)
    notify.background(phone.serial)
    friend = run.account('ideal_note')
    nickname = _one(run, f"profiles?id=eq.{friend['id']}&select=nickname").get('nickname') or ''
    check.reply('코드 입력', _api(run, 'POST', '/referral/redeem', friend['token'], {'code': code}), 200)
    want = (FRIEND_TITLE, f'{nickname} 님이 가입했어요, 리뷰를 남겨 주세요')
    new = notify.wait_new(phone.serial, before, seconds=30, match=lambda n: (n.title, n.text) == want)
    check.that(any((n.title, n.text) == want for n in new), f'30초 안에 알림 "{want[0]} / {want[1]}" 없음(새 알림 {len(new)}건: {notice_memo(new)})')
    return check.result()


# ── 공유 창 1 ───────────────────────────────────────────────────────────────────────────────────────

def p_ref_04(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    code = area4_set2._code(run, account['id'])
    text = f'CampusMate 에서 같이 해요! 가입할 때 추천 코드 {code} 를 넣어 줘.'
    note = []

    def sheet(said):
        time.sleep(3)  # 공유 창이 뜨기를 기다린다
        top = phone.top()
        check.that(tools.PACKAGE not in top, f'공유 창이 안 뜸 — 맨 앞이 아직 우리 앱({top[:80]})')
        if tools.PACKAGE in top:
            return
        if notify.screen_has(phone.serial, text):
            note.append('공유 창에서 초대 글 확인')
        if not _tap_label(phone.serial, SHARE_LABELS):
            tools.adb(phone.serial, 'shell', 'input', 'keyevent', 'KEYCODE_BACK')
            raise Blocked('공유 창에 "복사" 칸이 없음(이 기기 공유 창) — 사람 필요')
        time.sleep(1)

    said = _app(check, phone(midway=stepper(phone, sheet), token_hash=token, code=code))
    if said.get('result') == 'pass':
        check.that(said.get('clipboard') == text, f'클립보드 {said.get("clipboard")!r} ≠ 초대 글')
    return check.result('; '.join(note))


# ── 하트 모자람 (비AI) ──────────────────────────────────────────────────────────────────────────────

def p_heart_44(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    _add_avatar(run, account)
    _give(run, account, 9)
    _app(check, phone(token_hash=token))
    # 서버에 닿았는지 모호해도 다시 보내지 않는다 — 402 가 아니게 받아들여졌다면 그 요청이 곧 유료 AI 호출이다
    check.reply('API 다시 만들기', _api(run, 'POST', '/me/avatar/regenerate', account['token'], **_ONCE), 402, LOW_HEARTS)
    check.that(len(_avatars(run, account)) == 2, '생성 시도가 새로 생김(기대 0)')
    check.that(_balance(run, account) == 9, '잔액이 9 가 아님')
    return check.result()


# ── 실제 AI 3 (별도 묶음) ───────────────────────────────────────────────────────────────────────────

def _paid_calls(run, account, known):
    """이 가설에서 나간 유료 호출 수 — 앱의 "다시 만들기" 한 번이 새 아바타 시도 행(ready · pending · failed 무엇이든) 하나다."""
    return len([r for r in _avatars(run, account) if r['id'] not in known])


def _regen(case_name, extra_avatar, balance, cost):
    """완성 [1 + extra_avatar]장, 잔액 [balance] 에서 "다시 만들기" 한 번 — [cost] 는 이번 한 장의 값(0 이면 무료).
    메모에 유료 호출 횟수를 남기고, 비용이 나간 뒤에는 어떤 결과든 [_PAID] 에 적어 두 번째 부름이 같은 이유를 돌려주게 한다."""
    def case(run, phone):
        real_ai_gate()
        if case_name in _PAID:
            result, note = _PAID[case_name]
            if result == 'fail':  # 러너가 fail 을 한 번 더 돌려도 첫 시도의 이유가 사라지지 않게 그대로 돌려준다
                return result, f'{note} — 유료 호출 뒤라 다시 하지 않음'
            raise Blocked(f'이미 한 번 유료 호출 — 재시도 안 함(앞 결과 {result}: {note})')
        try:
            result = _regen_once(run, phone, case_name, extra_avatar, balance, cost)
        except Blocked as e:
            if case_name in _PAID:
                _PAID[case_name] = ('blocked', str(e))
            raise
        if case_name in _PAID:
            _PAID[case_name] = result
        return result
    return case


def _charge_evidence(run, account, known):
    """"만드는 중" 인데 잔액이 이미 달랐을 때의 증거 — 그 순간 새 시도 행의 상태 · 생성 시각과 avatar_regen 원장의 금액 · 시각.
    차감이 완성 전에 나간 결함인지, 읽기가 완성 뒤였는지를 사람이 가려 볼 수 있게."""
    try:
        rows = [r for r in _avatars_at(run, account) if r['id'] not in known]
        ledger = _rows(run, f"heart_transactions?profile_id=eq.{account['id']}&reason=eq.avatar_regen&select=amount,created_at")
    except Blocked as e:  # 증거를 못 읽어도 결함 후보 fail 은 그대로 남긴다 — 읽기 실패가 판정을 blocked 로 덮으면 안 된다
        return f'증거 읽기 실패: {e}'
    return (f"시도 행 {[(r.get('status'), r.get('created_at')) for r in rows] or '아직 없음'}, "
            f"원장 {[(r.get('amount'), r.get('created_at')) for r in ledger] or '없음'}")


def _avatars_at(run, account):
    return _rows(run, f"profile_avatars?profile_id=eq.{account['id']}&select=id,status,created_at")


def _regen_once(run, phone, case_name, extra_avatar, balance, cost):
    check = Check()
    account, token = _signed_in(run, 'home')
    if extra_avatar:
        _add_avatar(run, account)
    if balance:
        _give(run, account, balance)
    known = {r['id'] for r in _avatars(run, account)}
    made = {}
    seen = {'pending': False, 'flagged': False}  # 만드는 중(pending)인 시도를 읽은 적이 있나 · 잔액이 달라 이미 적었나

    def finished(said):
        _PAID[case_name] = ('blocked', '앱이 만들기를 누른 뒤 결과가 나오기 전에 멈춤')  # 여기부터는 비용이 나간다
        deadline = time.monotonic() + AI_WAIT
        while True:
            # 잔액을 먼저 읽는다 — 그다음 읽은 시도가 아직 pending 이면 이 값은 완성 전이다(area5_api 와 같은 순서).
            # 시도를 먼저 읽으면 방금 완성된 시도를 본 그 순간의 잔액이 이미 차감 뒤라 "만드는 중에 빠졌다" 고 틀리게 본다.
            during = _balance(run, account)
            new = [r for r in _avatars(run, account) if r['id'] not in known]
            if new and new[0]['status'] == 'failed':
                raise Blocked(f'아바타 생성이 실패(AI 쪽) — 앱 결함으로 세지 않는다 (유료 호출 {len(new)}번)')
            if new and new[0]['status'] == 'ready':
                made['id'] = new[0]['id']  # 이 반복의 잔액은 완성 직전 · 직후 어느 쪽인지 모른다 — 검사하지 않는다
                return
            seen['pending'] = seen['pending'] or bool(new)
            if during != balance and not seen['flagged']:
                seen['flagged'] = True  # 이유는 한 번만 — 증거는 이 순간 것이 필요하다
                check.that(False, f'만드는 중 잔액 {during}(기대 {balance} — 하트는 완성 뒤에 빠진다) — 완성 전인데 이미 차감됨(결함 후보); '
                                  f'{_charge_evidence(run, account, known)}')
            if time.monotonic() >= deadline:
                raise Blocked(f'{AI_WAIT}초 안에 새 아바타가 안 끝남 (새 아바타 시도 행 {len(new)}개 — 앱이 이미 눌렀으니 0개여도 서버에 닿았는지 확인 필요)')
            time.sleep(POLL)

    _app(check, _slow(phone, 600)(midway=stepper(phone, finished), token_hash=token, balance=balance, free=cost == 0))
    want = balance - cost
    _wait_for(lambda: _balance(run, account) == want, 60)  # 차감은 완성을 적은 뒤에 나간다
    check.that(_balance(run, account) == want, f'완성 뒤 잔액 {_balance(run, account)}(기대 {want})')
    ledger = _rows(run, f"heart_transactions?profile_id=eq.{account['id']}&reason=eq.avatar_regen&select=amount,ref_id")
    check.that([r['amount'] for r in ledger] == ([-cost] if cost else []), f'avatar_regen 원장 {ledger}(기대 {[-cost] if cost else []})')
    if cost and ledger:
        check.that(ledger[0].get('ref_id') == made.get('id'), '원장 ref_id 가 새 아바타 시도 id 와 다름')
    paid = f'유료 호출 {_paid_calls(run, account, known)}번(새 아바타 시도 행 수)'
    result, note = check.result()
    if result == 'pass' and cost and not seen['pending']:
        # 첫 읽기부터 이미 완성이었다 — 하트가 완성 뒤에 빠지는지는 "만드는 중" 값을 못 봐서 가릴 수 없다(완성 뒤 잔액 · 원장은 맞음)
        return 'blocked', f'읽기 전에 끝남 — 만드는 중 잔액을 측정 불가(완성 뒤 잔액 · 원장은 맞음) ({paid})'
    return result, f'{note} ({paid})' if note else paid


PHONE = {
    'E-HOME-09': _cut_case(), 'E-CARD-16': _cut_case(True), 'E-POLL-30': _cut_case(True), 'E-HEART-26': _cut_case(True),
    'E-REF-05': p_ref_05,
    'E-CARD-14': _waiting(TWICE_A_WEEK), 'E-CARD-15': _waiting(EVERY_DAY), 'E-CARD-35': p_card_35,
    'E-CARD-02': p_card_02, 'E-REF-18': p_ref_18,
    'E-REF-04': p_ref_04,
    'E-HEART-44': p_heart_44,
}
AI = {'E-HEART-42': _regen('E-HEART-42', False, 0, 0), 'E-HEART-43': _regen('E-HEART-43', True, 30, 10),
      'E-HEART-45': _regen('E-HEART-45', True, 10, 10)}

area1.PHONE.update(PHONE)
area1.PHONE.update(AI)
for _case in AI:  # 유료 AI 호출 — 앱 대기 600초 + 완성 대기 AI_WAIT 가 기본 상한 안에 안 들어간다
    tools.CASE_LIMITS[_case] = AI_WAIT + 600
area1.BUNDLES['area2-phone3'] = list(PHONE)
area1.BUNDLES['area2-phone3-ai'] = list(AI)
