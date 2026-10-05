"""영역 4 PUSH A1 — 받는 사람 폰 한 대 + 상대 행동은 API. 알림이 오는지 · 안 오는지만 `dumpsys notification` 으로 읽는다(묶음 area4-push-a1).
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 4 의 E-PUSH 줄(10-04 갱신본). 분류는 바탕화면 E2E_결과/영역갱신/push_분류표.md 의 A1.

가설 하나 = 함수 하나 `(scene)`. 폰 계정(받는 사람)을 홈까지 켜 기기 토큰이 서버에 올라오기를 기다린 뒤 앱을 HOME 으로 내리고,
상대(보내는 사람)는 계정 토큰으로 서버 API 를 불러 대신한다. 앱은 홈에서 3초만 머물고 판정은 전부 여기서 한다(앞 가설 E-ONB-61 과 같은 앱 동작).

시나리오와 다르게 도는 것(보고의 "확인 필요"):
  "안 온다"       알림이 0개인 것만으로는 읽기가 깨진 것과 구분이 안 된다. 같은 실행 안에서 대조 알림(메시지 또는 수락) 하나가 실제로 오는 것까지
                 봐야 pass 다 — 대조가 안 오면 fail 이 아니라 blocked("안 온다" 를 믿을 수 없음). 정지(70)는 정지 뒤엔 대조도 못 받아 정지 전에 한다.
  기다리는 시간   notify.NOTICE_WAIT(60초) — FCM 이 늦는 기기면 늘린다. 알림 도착 시각은 2초 단위 근사.
  "둘 다 1개"     폰이 하나라 받는 사람 쪽만 본다(21 의 B 쪽 1개 · 37 의 B 쪽 1개). 한 사람 몫은 matches 행 수 · trust_passed_at 으로 대신한다.
  "1개"          알림이 온 뒤 SETTLE(20초) 더 지켜봐 같은 알림이 또 오면 fail(10 · 17 · 18 · 21 · 24 · 35 · 37 · 49). 25 · 26 은 문구만 본다.
  낮에만          서울 08~22시 — 밤엔 방해 금지 시간 때문에 결과가 달라진다(notify.require_daytime).
"""

import functools
import re
import secrets
import time

from e2e import area1, area2, area2_phone3, area3, area3_phone, notify, tools
from e2e import notify_factory as factory
from e2e.area1 import Check, _api, _app, _rows
from e2e.area2_phone3 import _wait_for, notice_memo
from e2e.area3_phone import _permitted
from e2e.tools import Blocked

TOKEN_WAIT = 30  # 기기 토큰이 서버에 올라오기를 기다리는 초(area2_phone3 p_card_02 와 같다)
NOTICE_WAIT = notify.NOTICE_WAIT  # 알림이 오는지 · 안 오는지 지켜보는 초(시나리오 4-1 의 T)
CONTROL_WAIT = 30  # 대조 알림을 기다리는 초
SETTLE = 20  # 알림이 온 뒤 같은 알림이 또 오는지 더 보는 초
CASE_LIMIT_SLOW = 900  # 60초 지켜보기 + 대조 + 앱 켜기가 겹쳐 기본 420초를 넘는 가설

ACCEPT_TITLE = '나를 수락한 사람이 있어요'
MATCH_TITLE = '매칭됐어요!'
PUBLIC_TITLE = '카카오톡 아이디를 주고받았어요'
REVIEW_TITLE = '새 지인 리뷰가 도착했어요'
TRUST_BODY = '카카오톡 아이디·실사진 공개를 수락했어요'
CHANNEL = 'campus_mate_default'
CHANNEL_NAME = 'CampusMate 알림'
HIGH = 4  # NotificationManager.IMPORTANCE_HIGH


def accept_body(nickname):
    return f'{nickname} 님이 대화를 하고 싶어 해요'


def _matched(nickname):
    return f'{nickname} 님도 수락했어요'


def _started(nickname):
    return f'{nickname} 님과 대화를 시작해 보세요'


def _public(nickname):
    return f'{nickname} 님의 프로필이 공개됐어요'


def _channel_importance(dump):
    """채널 목록에서 campus_mate_default 줄의 (이름이 CampusMate 알림인지, 중요도). 그 줄을 못 읽으면 None — 기기마다 모양이 다르다."""
    for line in (dump or '').splitlines():
        found = re.search(rf"mId='?{CHANNEL}'?.*?mImportance=(\d)", line)
        if found:
            return CHANNEL_NAME in line, int(found.group(1))
    return None


def _one_match(s):
    """폰 계정과 상대 사이 matches 가 정확히 1행."""
    low, high = sorted((s.me['id'], s.partner['id']))
    rows = _rows(s.run, f'matches?profile_a=eq.{low}&profile_b=eq.{high}&select=id')
    s.check.that(len(rows) == 1, f'matches {len(rows)}행(기대 1)')


class _Scene:
    """폰 계정 [me] · 상대 [partner] 와 지켜보기 도구 — 만들면 앱이 홈에 닿고 토큰이 올라온 뒤 HOME 에 내려가 있다."""

    def __init__(self, run, phone):
        notify.require_daytime()
        self.run, self.phone, self.check, self.notes = run, phone, Check(), []
        self.me = area3_phone._person(run)
        self.partner = area3_phone._person(run)
        self.ready = False
        _app(self.check, phone(token_hash=run.link(self.me['email'])))
        if self.check.problems:  # 홈에 못 닿았으면 토큰도 알림도 기대할 수 없다
            return
        if not _wait_for(lambda: _rows(run, f"push_tokens?profile_id=eq.{self.me['id']}&select=token"), TOKEN_WAIT):
            raise Blocked(f'{TOKEN_WAIT}초 안에 기기 토큰이 서버에 안 올라옴 — 알림 권한 · FCM 확인')
        notify.background(phone.serial)  # 앱이 앞에 있으면 배너가 안 뜬다
        self.ready = True

    @property
    def nick(self):
        return self.partner['nickname']

    def before(self):
        """앞에 남은 알림과 섞이지 않게 — 이 뒤에 새로 생긴 것만 본다."""
        return notify.read_notifications(self.phone.serial)

    def _await(self, before, want, seconds):
        new = notify.wait_new(self.phone.serial, before, seconds=seconds, match=lambda n: (n.title, n.text) == want)
        return [n for n in new if (n.title, n.text) == want], new

    def arrives(self, before, title, text, seconds=NOTICE_WAIT, once=False):
        got, new = self._await(before, (title, text), seconds)
        self.check.that(got, f'{seconds}초 안에 알림 "{title} / {text}" 없음(새 알림 {len(new)}건: {notice_memo(new)})')
        if got and once:
            more = [n for n in notify.expect_none(self.phone.serial, before + new, seconds=SETTLE) if (n.title, n.text) == (title, text)]
            count = len(got) + len(more)
            self.check.that(count == 1, f'같은 알림이 {count}개(기대 1)')
        return got

    def proof(self, before, title, text):
        """"안 온다" 를 믿을 근거 — 이 알림이 오면 읽기 · 토큰 · FCM 이 살아 있다. 안 오면 [Blocked]."""
        got, _ = self._await(before, (title, text), CONTROL_WAIT)
        if not got:
            raise Blocked(f'대조 알림 "{title} / {text}" 이 {CONTROL_WAIT}초 안에 안 옴 — 알림 길(읽기 · 토큰 · FCM)이 살아 있는지 몰라 "안 온다" 를 믿을 수 없음')

    def silent(self, before, only=None, control='message'):
        """[NOTICE_WAIT] 초 내내 [only] 에 걸리는 새 알림이 0개여야 한다. 0개면 [control] 로 길이 살아 있음을 한 번 더 본다(None 이면 건너뜀)."""
        seen = [n for n in notify.expect_none(self.phone.serial, before, seconds=NOTICE_WAIT) if only is None or only(n)]
        self.check.that(not seen, f'안 와야 할 알림이 {len(seen)}건 옴: {notice_memo(seen)}')
        if not seen and control:
            self.control(control)

    def control(self, kind):
        """대조 알림 — 'message'(상대가 새 방에서 메시지) 또는 'accept'(상대가 카드를 수락). 스위치를 끈 종류로는 대조할 수 없다."""
        ctl = area3_phone._person(self.run)
        before = self.before()
        if kind == 'message':
            body = f'E2E-ctl-{secrets.token_hex(3)}'
            factory.send(self.run, ctl, factory.match(self.run, self.me, ctl), body)
            want = (ctl['nickname'], body)
        else:
            factory.accept_card(self.run, ctl, factory.card(self.run, ctl, self.me))
            want = (ACCEPT_TITLE, accept_body(ctl['nickname']))
        self.proof(before, *want)

    def reply(self, label, reply, *statuses):
        self.check.that(reply[0] in statuses, f'{label} {reply[0]}(기대 {"/".join(map(str, statuses))})')

    def matched(self, label, body):
        self.check.that((body or {}).get('matched') is True, f'{label}: matched {(body or {}).get("matched")!r}(기대 True)')


def _case(fn):
    @functools.wraps(fn)
    def wrapped(run, phone):
        scene = _Scene(run, phone)
        if scene.ready:
            fn(scene)
        return scene.check.result('; '.join(scene.notes))
    return _permitted(wrapped)


# ── 카드 · 수락 · 매칭 ──────────────────────────────────────────────────────────────────────────

@_case
def push_10(s):
    card = factory.card(s.run, s.partner, s.me)
    before = s.before()
    factory.accept_card(s.run, s.partner, card)
    s.arrives(before, ACCEPT_TITLE, accept_body(s.nick), once=True)


@_case
def push_12(s):
    card = factory.card(s.run, s.partner, s.me)
    before = s.before()
    factory.reject_card(s.run, s.partner, card)
    rows = _rows(s.run, f'card_decisions?card_id=eq.{card}&select=decision')
    s.check.that([r['decision'] for r in rows] == ['reject'], f'card_decisions {rows}(기대 reject 한 줄)')
    s.silent(before)


@_case
def push_13(s):
    factory.switches(s.run, s.me, acceptance_received=False)
    card = factory.card(s.run, s.partner, s.me)
    before = s.before()
    factory.accept_card(s.run, s.partner, card)
    status, body = _api(s.run, 'GET', '/cards/acceptances', s.me['token'])
    listed = [a.get('card_id') for a in (body or {}).get('acceptances', [])] if status == 200 else []
    s.check.that(card in listed, f'받은 수락 목록({status})에 그 카드가 없음: {listed}')
    s.silent(before)


@_case
def push_17(s):
    card = factory.card(s.run, s.me, s.partner)
    factory.accept_card(s.run, s.me, card)
    before = s.before()
    s.matched('상대가 받은 수락을 수락', factory.accept_back(s.run, s.partner, card))
    _one_match(s)
    s.arrives(before, MATCH_TITLE, _matched(s.nick), once=True)


@_case
def push_18(s):
    card = factory.card(s.run, s.partner, s.me)
    factory.accept_card(s.run, s.partner, card)
    before = s.before()  # 앞서 온 "나를 수락한 사람" 알림이 늦게 떠도 문구로 가려 보니 판정에 안 섞인다
    s.matched('폰 계정이 받은 수락을 수락', factory.accept_back(s.run, s.me, card))
    s.arrives(before, MATCH_TITLE, _started(s.nick), once=True)


@_case
def push_21(s):
    mine, theirs = factory.card(s.run, s.me, s.partner), factory.card(s.run, s.partner, s.me)
    factory.accept_card(s.run, s.me, mine)
    factory.accept_card(s.run, s.partner, theirs)
    before = s.before()
    s.matched('상대의 받은 수락 수락', factory.accept_back(s.run, s.partner, mine))
    factory.accept_back(s.run, s.me, theirs)  # 이미 있는 매칭을 다시 본다 — 알림은 더 가면 안 된다
    _one_match(s)
    s.arrives(before, MATCH_TITLE, _matched(s.nick), once=True)
    s.notes.append('상대(B) 쪽 알림 1개는 폰이 하나라 못 봄 — matches 1행으로 대신')


@_case
def push_22(s):
    factory.switches(s.run, s.me, match_made=False)
    card = factory.card(s.run, s.me, s.partner)
    factory.accept_card(s.run, s.me, card)
    before = s.before()
    s.matched('상대의 받은 수락 수락', factory.accept_back(s.run, s.partner, card))
    s.silent(before, only=lambda n: n.title == MATCH_TITLE)
    s.notes.append('상대 쪽은 받는다는 것은 폰이 하나라 못 봄(21 의 같은 경로가 본다)')


# ── 메시지 ────────────────────────────────────────────────────────────────────────────────────

def _message(s, text, want):
    match_id = factory.match(s.run, s.me, s.partner)
    before = s.before()
    factory.send(s.run, s.partner, match_id, text)
    s.arrives(before, s.nick, want, once=True)


@_case
def push_24(s):
    _message(s, '안녕하세요', '안녕하세요')


@_case
def push_25(s):
    text = f'E2E25-{secrets.token_hex(3)}'.ljust(45, 'x')
    _message(s, text, text[:40])


@_case
def push_26(s):
    _message(s, '첫줄\n둘째줄', '첫줄 둘째줄')


@_case
def push_32(s):
    factory.switches(s.run, s.me, new_message=False)
    match_id = factory.match(s.run, s.me, s.partner)
    before = s.before()
    factory.send(s.run, s.partner, match_id, f'E2E-32-{secrets.token_hex(3)}')  # 저장은 201 이어야 한다
    s.silent(before, only=lambda n: n.title == s.nick, control='accept')


@_case
def push_34(s):
    match_id = factory.match(s.run, s.me, s.partner)
    s.reply('나가기', _api(s.run, 'POST', f'/chat/matches/{match_id}/leave', s.me['token']), 200)
    before = s.before()
    s.reply('나간 방에 보내기', area3._send(s.run, s.partner, match_id, f'E2E-34-{secrets.token_hex(3)}'), 409)
    s.silent(before, only=lambda n: n.title == s.nick)


# ── 신뢰 확인 ─────────────────────────────────────────────────────────────────────────────────

@_case
def push_35(s):
    match_id = factory.match(s.run, s.me, s.partner)
    before = s.before()
    factory.trust(s.run, s.partner, match_id)
    s.arrives(before, s.nick, TRUST_BODY, once=True)


@_case
def push_36(s):
    factory.switches(s.run, s.me, new_message=False)
    match_id = factory.match(s.run, s.me, s.partner)
    before = s.before()
    factory.trust(s.run, s.partner, match_id)
    s.silent(before, only=lambda n: n.title == s.nick, control='accept')


@_case
def push_37(s):
    match_id = factory.match(s.run, s.me, s.partner)
    factory.trust(s.run, s.me, match_id)  # 폰 계정이 먼저 수락해 기다린다
    before = s.before()
    factory.trust(s.run, s.partner, match_id)
    s.arrives(before, PUBLIC_TITLE, _public(s.nick), once=True)
    s.arrives(before, s.nick, TRUST_BODY, once=True)  # 상대의 수락은 새 메시지 알림으로도 온다
    rows = _rows(s.run, f'matches?id=eq.{match_id}&select=trust_passed_at')
    s.check.that(rows and rows[0].get('trust_passed_at'), f'trust_passed_at {rows}(찍혀야 함)')
    s.notes.append('상대(B) 쪽 공개 알림 1개는 폰이 하나라 못 봄 — trust_passed_at 으로 대신')


@_case
def push_39(s):
    match_id = factory.match(s.run, s.me, s.partner)
    factory.trust(s.run, s.me, match_id)
    factory.switches(s.run, s.me, match_made=False)
    before = s.before()
    factory.trust(s.run, s.partner, match_id)
    s.proof(before, s.nick, TRUST_BODY)  # 새 메시지 알림은 온다 — 길이 살아 있다는 증거를 겸한다
    s.silent(before, only=lambda n: n.title == PUBLIC_TITLE, control=None)


# ── 지인 리뷰 · 추천 ──────────────────────────────────────────────────────────────────────────

def _reviews(s):
    return _rows(s.run, f"friend_reviews?reviewee_id=eq.{s.me['id']}&select=id")


@_case
def push_49(s):
    factory.link(s.run, s.partner, s.me)
    before = s.before()
    factory.review(s.run, s.partner, s.me)
    s.arrives(before, REVIEW_TITLE, f'{s.nick} 님이 리뷰를 남겼어요', once=True)
    s.check.that(len(_reviews(s)) == 1, 'friend_reviews 가 1행이 아님')


@_case
def push_51(s):
    factory.switches(s.run, s.me, new_friend_review=False)
    factory.link(s.run, s.partner, s.me)
    before = s.before()
    factory.review(s.run, s.partner, s.me)  # 저장은 201 이어야 한다
    s.check.that(len(_reviews(s)) == 1, 'friend_reviews 가 1행이 아님')
    s.silent(before, only=lambda n: n.title == REVIEW_TITLE)


# ── 정지 · 채널 ───────────────────────────────────────────────────────────────────────────────

@_case
def push_70(s):
    s.control('message')  # 정지 뒤에는 대조 알림도 못 받는다 — 길은 정지 전에 증명한다
    factory.link(s.run, s.me, s.partner)  # 리뷰를 쓸 수 있는 사이(상대를 active 로 올린다 — 정지는 폰 계정만)
    match_id = factory.match(s.run, s.me, s.partner)
    area2._guard(s.run, s.me['id'])
    area3._patch(s.run, f"profiles?id=eq.{s.me['id']}", {'status': 'suspended'})
    before = s.before()
    s.reply('정지된 사람에게 메시지', area3._send(s.run, s.partner, match_id, f'E2E-70-{secrets.token_hex(3)}'), 404, 409)
    s.reply('정지된 사람에게 리뷰', area3._review_post(s.run, s.partner, s.me), 404, 409)
    s.silent(before, control=None)


@_case
def push_74(s):
    match_id = factory.match(s.run, s.me, s.partner)
    text = f'E2E-74-{secrets.token_hex(3)}'
    before = s.before()
    factory.send(s.run, s.partner, match_id, text)
    got = s.arrives(before, s.nick, text)
    if not got:
        return
    s.check.that(got[0].channel == CHANNEL, f'채널 {got[0].channel!r}(기대 {CHANNEL!r} — fcm_fallback_notification_channel 이면 회귀)')
    found = _channel_importance(tools.adb(s.phone.serial, 'shell', 'dumpsys', 'notification', '--noredact', check=False))
    if found is None:
        if s.check.problems:
            return
        # 알림이 들어간 채널 id 는 맞았다 — 나머지(이름 · 중요도 4)는 이 기기 dumpsys 모양을 못 읽어 사람이 본다. pass 로 묻어 두지 않는다
        raise Blocked(f'채널 목록 줄을 못 읽음(이 기기 dumpsys 모양) — 알림이 들어간 채널 {CHANNEL} 은 맞음 · 이름 "{CHANNEL_NAME}" 과 중요도 {HIGH} 는 사람이 확인')
    named, importance = found
    s.check.that(named, f'채널 이름이 "{CHANNEL_NAME}" 이 아님')
    s.check.that(importance == HIGH, f'채널 중요도 {importance}(기대 {HIGH})')


PHONE = {
    'E-PUSH-10': push_10, 'E-PUSH-12': push_12, 'E-PUSH-13': push_13, 'E-PUSH-17': push_17, 'E-PUSH-18': push_18,
    'E-PUSH-21': push_21, 'E-PUSH-22': push_22, 'E-PUSH-24': push_24, 'E-PUSH-25': push_25, 'E-PUSH-26': push_26,
    'E-PUSH-32': push_32, 'E-PUSH-34': push_34, 'E-PUSH-35': push_35, 'E-PUSH-36': push_36, 'E-PUSH-37': push_37,
    'E-PUSH-39': push_39, 'E-PUSH-49': push_49, 'E-PUSH-51': push_51,
    'E-PUSH-54': _permitted(area2_phone3.p_ref_18),  # 영역 2 E-REF-18 과 같은 일(추천 코드 → 추천인 알림) — 한 번 돌려 두 번호에 기록
    'E-PUSH-70': push_70, 'E-PUSH-74': push_74,
}

tools.CASE_LIMITS.update({case: CASE_LIMIT_SLOW for case in (
    'E-PUSH-12', 'E-PUSH-13', 'E-PUSH-21', 'E-PUSH-22', 'E-PUSH-32', 'E-PUSH-34', 'E-PUSH-36', 'E-PUSH-39', 'E-PUSH-51', 'E-PUSH-70')})

area1.PHONE.update(PHONE)
area1.BUNDLES['area4-push-a1'] = list(PHONE)
