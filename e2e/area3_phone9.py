"""영역 3 지인 리뷰 알림 4개 — 단일 폰 3개(묶음 area3-phone-9: E-REV-16 · 17 · 26) + 두 기기 1개(묶음 area3-two-rev: E-REV-41).
기대값은 바탕화면 E2E_최종테스트_시나리오.md 의 그 줄이되 코드가 기준이다. 앱 쪽은 새 로직이 41 하나뿐이다(frontend/integration_test/area3_b9.dart).
알림 읽기 · 누르기 · "안 온다" 대조는 영역 4 알림 판(area4_push · area4_push_tap)의 것을 그대로 쓴다.

가설마다 방식:
  E-REV-16  단일 폰 — 폰 계정이 B(받는 쪽), A 의 "남기기" 는 PC 가 API 로. 앱은 E-PUSH-50 과 같은 판(홈에서 멈춤 → PC 가 HOME · 알림 1건 확인 · 누름 → 받은 리뷰 화면).
            "1건" 은 알림이 온 뒤 area4_push.SETTLE 초 더 지켜봐 같은 알림이 또 오면 fail.
  E-REV-17  단일 폰 — E-PUSH-51(새 지인 리뷰 스위치 끔 → 알림 0 · 리뷰 1행)과 같은 판이라 별칭으로 돌리고 결과를 두 번호에 적는다(area3_phone7 과 같다).
            스위치는 앱 16d 대신 같은 서버 길(PATCH /cards/notification-settings)로 끈다.
  E-REV-26  단일 폰 — A 가 API 로 쓰고(쓰기 알림이 오는 것으로 알림 길이 살아 있음을 먼저 본다) API 로 지운다 → 그 뒤 NOTICE_WAIT 초 동안 우리 앱 알림 0건 · 행 0.
            앱에서 휴지통으로 지우는 길은 E-REV-24 가 본다. 근거: 2026-09-29-friend-review-delete.md 결정 6(푸시 없음).
  E-REV-41  두 기기(twodev.TWO, A=폰 · B=에뮬) — B 화면(온보딩 20 에서 코드 → 20b 시트 → 닫으면 20d)과 A 화면(알림 → 20b)이 둘 다 필요하다.
            A 알림 1건 · 문구 · 누르기는 PC, 두 시트의 상대가 맞는지는 앱이 must 로 본다(twodev 는 앱의 말을 PC 에 돌려주지 않는다).
            "B 가 20b 에서 리뷰를 남기고 20d" 갈래는 안 본다(닫는 갈래만 — E-ONB-60 과 같다).
            낮 10~20시(시나리오)를 지금과 PREP_MINUTES 뒤 둘 다 계정을 만들기 전에 본다(area3_phone5._midday). 배치는 안 부른다 — 낮에는 알림이 바로 간다(cards/push.py).
"""

import time
from datetime import timedelta

from e2e import area1, area3, area3_phone5, area4_push, batch_gate, notify, tools, twodev
from e2e import notify_factory as factory
from e2e.area1 import Check, _api, _app, _rows
from e2e.area1_b2 import _code
from e2e.area2_phone3 import FRIEND_TITLE, _wait_for, notice_memo
from e2e.area2_two_accept import _verdict
from e2e.area3_phone import _permitted, _person
from e2e.area4_push import NOTICE_WAIT, REVIEW_TITLE, SETTLE, TOKEN_WAIT
from e2e.area4_push_tap import _judge
from e2e.tools import Blocked

PEER = 420  # 상대 기기가 일을 끝내기를 기다리는 초
PREP_MINUTES = 15  # 41 하나가 끝날 때까지 — 이만큼 뒤에도 낮 10~20시여야 시작한다
LIMITS = {'side_timeout': {'A': 600, 'B': 420}, 'deadline': 900}
CASE_LIMIT_TAP = 600  # 토큰 30 · 알림 60 · 한 건 확인 20 · 앱 90 이 겹친다
CASE_LIMIT_SILENT = 900  # 대조 30 · 지켜보기 60 · 앱 켜기
CASE_LIMIT_TWO = 1200


def _token_up(run, account):
    if not _wait_for(lambda: _rows(run, f"push_tokens?profile_id=eq.{account['id']}&select=token"), TOKEN_WAIT):
        raise Blocked(f'{TOKEN_WAIT}초 안에 기기 토큰이 서버에 안 올라옴 — 알림 권한 · FCM 확인')


def _once(check, serial, before, want):
    """[want] 알림이 NOTICE_WAIT 초 안에 오고 SETTLE 초 더 지켜봐도 한 건인지. 왔으면 True."""
    new = notify.wait_new(serial, before, seconds=NOTICE_WAIT, match=lambda n: (n.title, n.text) == want)
    got = [n for n in new if (n.title, n.text) == want]
    check.that(got, f'{NOTICE_WAIT}초 안에 알림 "{want[0]} / {want[1]}" 없음(새 알림 {len(new)}건: {notice_memo(new)})')
    if got:
        more = [n for n in notify.expect_none(serial, before + new, seconds=SETTLE) if (n.title, n.text) == want]
        check.that(len(got) + len(more) == 1, f'같은 알림이 {len(got) + len(more)}개(기대 1)')
    return bool(got)


# ── E-REV-16 ────────────────────────────────────────────────────────────────────────────────────────

def p_rev_16(run, phone):
    """A(상대)가 리뷰를 남기면 폰 계정 B 에게 알림 1건 — 누르면 받은 리뷰 화면에 A 의 카드."""
    notify.require_daytime()
    notify.ensure_delivery(phone.serial)
    check = Check()
    me, partner = _person(run), _person(run)
    factory.link(run, partner, me)
    want = (REVIEW_TITLE, f"{partner['nickname']} 님이 리뷰를 남겼어요")  # friend_reviews/router.py:160-166
    job = {'nickname': partner['nickname'], 'dest': 'reviews'}
    seen = {}

    def hold(said):
        _token_up(run, me)
        before = notify.read_notifications(phone.serial)
        notify.background(phone.serial)  # 앱이 앞에 있으면 배너가 안 뜬다
        factory.review(run, partner, me)
        seen['tapped'] = _once(check, phone.serial, before, want)
        if seen['tapped']:
            notify.tap_notification(phone.serial, *want)
            time.sleep(1)

    said = _app(check, phone(midway=hold, token_hash=run.link(me['email']), phase='hold', **job))
    if seen.get('tapped'):
        _judge(check, said, job)
    return check.result()


# ── E-REV-17 = E-PUSH-51 ────────────────────────────────────────────────────────────────────────────

def _twin(mine, theirs):
    area4_push.PHONE[theirs]  # 원본이 없어지면 등록하는 순간 터진다

    def run_as_twin(run, phone):
        try:
            result, note = area4_push.PHONE[theirs](run, phone)
        except Blocked as e:
            result, note = 'blocked', str(e)
        run.record(theirs, result, f'{mine} 로 돌린 같은 판' + (f' — {note}' if note else ''))
        return result, note
    return run_as_twin


# ── E-REV-26 ────────────────────────────────────────────────────────────────────────────────────────

@area4_push._case
def p_rev_26(s):
    """A(상대)가 쓴 리뷰를 지운다 → 폰 계정 B 에게 알림 0건 · 행 0."""
    factory.link(s.run, s.partner, s.me)
    before = s.before()
    status, body = area3._review_post(s.run, s.partner, s.me)
    if status != 201 or not (body or {}).get('id'):
        raise Blocked(f'준비: 리뷰 쓰기 {status} {body}')
    s.proof(before, REVIEW_TITLE, f'{s.nick} 님이 리뷰를 남겼어요')  # 쓰기 알림이 왔다 = 알림 길이 살아 있다, 그리고 지우기 뒤에 섞이지 않는다
    before = s.before()
    s.reply('A 지우기', _api(s.run, 'DELETE', f"/friend-reviews/{body['id']}", s.partner['token']), 204)
    left = _rows(s.run, f"friend_reviews?id=eq.{body['id']}&select=id")
    s.check.that(not left, f'friend_reviews {len(left)}행(기대 0 — 지웠다)')
    s.silent(before, control=None)


# ── E-REV-41 두 기기 ────────────────────────────────────────────────────────────────────────────────

def two_41(run, two):
    """B 가 온보딩 20 에서 A 의 추천 코드를 넣으면 B 에게 20b(A 에게 쓰기) → 닫으면 20d, A 에게 "친구가 가입했어요" 1건 → 누르면 20b(B 에게 쓰기)."""
    now = batch_gate.now_seoul()
    for later in (0, PREP_MINUTES):
        area3_phone5._midday(now + timedelta(minutes=later))
    serial = tools.serial('A', run.cfg)
    notify.ensure_delivery(serial)
    try:
        notify.grant_notifications(serial)  # 권한 창이 A 앱을 가리지 않게 — 끝나면(예외여도) 되돌린다
    except Blocked:
        pass  # 안드로이드 12 이하는 이 권한이 없다 = 권한 창도 없다. 그대로 진행(area3_phone._permitted 와 같다)
    try:
        return _two_41(run, two, serial)
    finally:
        notify.revoke_notifications(serial)


def _two_41(run, two, serial):
    check = Check()
    a = _person(run)
    code = _code(run, a['id'])
    nickname = area1._nickname()
    b = {**run.account('ideal_note', nickname=nickname), 'nickname': nickname}  # 06-3 직전 — 앱이 자기소개를 내고 20 에 닿는다
    want = (FRIEND_TITLE, f'{nickname} 님이 가입했어요, 리뷰를 남겨 주세요')  # friend_reviews/router.py:179-190

    def _after(sync, name, who):
        if not sync.wait(name, PEER):
            raise Blocked(f'{who} 가 {PEER}초 안에 끝내지 않음')

    def a_holding(said, sync):
        _token_up(run, a)
        before = notify.read_notifications(serial)
        notify.background(serial)
        sync.set('a-ready')
        _after(sync, 'b-redeemed', 'B')
        tapped = _once(check, serial, before, want)
        if tapped:
            notify.tap_notification(serial, *want)
        return {'tapped': tapped}

    def b_code(said, sync):
        _after(sync, 'a-ready', 'A')  # A 가 HOME 에 내려가 알림을 기다릴 준비가 된 뒤에 코드를 넣는다

    def b_redeemed(said, sync):
        rows = _rows(run, f"referrals?referee_id=eq.{b['id']}&select=referrer_id")
        check.that(rows == [{'referrer_id': a['id']}], f"referrals {rows}(기대 추천인 A {a['id']})")
        sync.set('b-redeemed')

    result, memo = two({('A', 'holding'): a_holding, ('B', 'code'): b_code, ('B', 'redeemed'): b_redeemed},
                       a_job={'token_hash': run.link(a['email']), 'friend_id': b['id']},
                       b_job={'token_hash': run.link(b['email']), 'code': code, 'referrer_id': a['id']}, **LIMITS)
    return _verdict(check, result, memo, 'B 가 20b 에서 리뷰를 남기는 갈래는 안 봄(닫는 갈래만)')


def _guarded(case):
    def wrapped(run, two):
        try:
            return case(run, two)
        except Blocked as e:
            return 'blocked', str(e)
    return wrapped


# ── 등록 ────────────────────────────────────────────────────────────────────────────────────────────

PHONE9 = {'E-REV-16': _permitted(p_rev_16), 'E-REV-17': _twin('E-REV-17', 'E-PUSH-51'), 'E-REV-26': p_rev_26}
TWO = {'E-REV-41': _guarded(two_41)}

tools.CASE_LIMITS.update({'E-REV-16': CASE_LIMIT_TAP, 'E-REV-17': tools.CASE_LIMITS['E-PUSH-51'], 'E-REV-26': CASE_LIMIT_SILENT,
                          'E-REV-41': CASE_LIMIT_TWO})
area1.PHONE.update(PHONE9)
twodev.TWO.update(TWO)
area3.BUNDLES['area3-phone-9'] = list(PHONE9)
area3.BUNDLES['area3-two-rev'] = list(TWO)
