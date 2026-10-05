"""영역 4 PUSH 밤·아침·시각 경계 13개 — 15 · 16 · 23 · 33 · 52 · 72 · 73 · 83~88. 받는 사람 폰 한 대 + 상대 행동은 API(area4_push 와 같다).
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 4 의 E-PUSH 줄(10-04 갱신본)이되, 코드가 다르면 코드가 기준이다
(backend/app/cards/push.py · cards/router.py · chat/router.py · friend_reviews/router.py · referral/router.py). 앱 쪽은 area4_push_night.dart(전부 E-ONB-61 별칭).

번들: `area4-push-night`(13개 전부) · `area4-push-night-a`(밤 단계가 있는 11개) · `area4-push-edge`(72 · 73).

밤(22~8시)에는 알림 종류에 따라 서버가 `pending_pushes` 에 보관했다가 아침에 08시 예약 chat-gate 가 보낸다. 그런데 그 알림은 **그 순간 토큰을 가진 계정**에게만
간다 — 같은 밤에 여러 가설을 돌리면 아침 관측이 서로 먹는다. 그래서 두 단계로 나눈다(E-CARD-44 와 같은 상태 파일 방식, 같은 번호를 두 번 돌린다).
  밤 단계   22:00~23:59. 상대 행동 → 받는 사람 알림 0개(대조로 새 메시지는 온다) · 보관 행의 kind · route · 개수 → 행 내용을 `night_<번호>.json` 에 적고 **행을 지운다**
            (08시 예약 chat-gate 가 먹지 못하게). 끝은 blocked + 다음 단계 안내.
  아침 단계 다음 날 낮(08:06~21:48 의 hh:06~hh:48 분 — 85 만 07:06~07:48). 받는 사람 계정으로 다시 로그인해 토큰을 되찾고, 기록한 행을 새 id 로 **심고 곧바로**
            손으로 chat-gate 를 부른다(관문 area2._batch). 앵커 = 심은 행이 사라짐. 그다음 알림을 판정한다.
15 의 "다음날 08시대" 와 달리 아침 단계는 **밤사이 정말 쌓인 행이 아니라 밤에 서버가 만든 행의 복원**이다. 문구 · kind · route · 묶음 규칙은 같지만 08:00 예약 실행이
직접 만든 행은 아니다(예약 실행 자체는 85 가 본다).
단일 단계: 16 · 33(밤에 끝) · 72 · 73(경계 시각에 끝).

시나리오와 다르게 도는 것(보고의 "확인 필요"):
  배치 응답        시나리오가 적은 `deferred_sent` 개수는 스케줄러 호출이라 못 읽는다 — 보관 행이 사라진 것 · 알림창으로 대신한다.
  "누르면 이동"    15 · 83(대화 목록) · 87(받은 리뷰 목록)의 알림 눌러 이동은 이 PR 범위 밖이다(알림 문구 · 개수만 본다).
  23              R 이 카드를 먼저 수락하면 상대(partner)에게도 "받은 수락" 보관 행이 생긴다. 시나리오의 "상대 0행" 은 **match_made 행**만 센다(그 행은 방금 누른 쪽이라 버려진다).
  86              R 쪽에는 상대의 신뢰 수락이 "새 메시지" 로 밤에도 온다 — 공개 알림(제목 PUBLIC_TITLE)만 가려 본다. 대조도 그 메시지(제목 상대 닉네임)가 겸한다.
  87              추천 연결은 R 이 추천인, 두 상대가 가입자다(referrals 기본키가 referee_id 라 R 한 사람이 둘의 추천을 받을 수 없다). 지인 리뷰 작성은 어느 방향이든 된다.
  88              알림 제목은 코드대로 "친구가 가입했어요", 본문 "{닉네임} 님이 가입했어요, 리뷰를 남겨 주세요".
  72 · 73          서버 시계는 못 읽는다 — PC 시각으로 첫 수락은 경계 40초 전, 둘째는 20초 뒤에 보내고 재 둔 시각을 메모에 적는다. 첫 수락이 경계를 넘겼거나
                  둘째가 경계 전이면 blocked("경계를 못 맞춤"). 73 은 08:00 예약 실행이 첫 보관분을 따로 보낼 수 있어 그 알림(문구가 다르다)은 판정에서 빼고 메모한다.
  85              07시대 손 호출 → 그대로 두는지 → 08:00 예약 실행이 보낼 때까지(08:03 까지) 기다린다. 안 보냈으면 08:06 뒤 손으로 한 번 더 불러 보내지는 것까지 보고
                  메모에 "예약 실행이 안 보냄 — 확인 필요" 를 남긴다(결과는 pass: 07시대 규칙은 이미 봤다).
운영 순서: chat-gate 는 같은 시(時)에 손으로 두 번 못 부른다(batch_gate) — 아침 단계는 가설 하나가 시(時) 하나를 쓴다. 같은 시의 둘째는 심기 전에 blocked("다음 시 06분에 다시").
  가장 먼저 85(07:06~07:48), 73(07:50~07:58), 그다음 08시부터 시(時)마다 하나씩. 72 는 21:50~21:58 에 시작하고 밤 단계들은 22:00 뒤에.
"기다리는 시간"  area4_push 와 같다(NOTICE_WAIT 60초 · 대조 30초 · 도착 뒤 20초). 알림이 늦는 기기면 늘린다.
"""

import json
import time
from datetime import date, timedelta

from e2e import area1, area2, area2_time_device as td, area3, area3_phone, area4_set2, batch_gate, notify, tools
from e2e import notify_factory as factory
from e2e.area1 import Check, _api, _app, _one, _rows
from e2e.area2_phone3 import FRIEND_TITLE, _wait_for, notice_memo
from e2e.area3_phone import _permitted
from e2e.area4_push import (ACCEPT_TITLE, MATCH_TITLE, NOTICE_WAIT, PUBLIC_TITLE, REVIEW_TITLE, SETTLE, TOKEN_WAIT, TRUST_BODY, _matched,
                            _one_match, _public, _reviews, _Scene, accept_body)
from e2e.tools import Blocked

CARD_WAIT = td.CARD_WAIT  # 배치 뒤 보관 행이 사라질 때까지(초)
DAY_HOURS = range(8, 22)  # 아침 단계의 손 호출 시(時) — 08:06~21:48
EARLY_HOURS = (7,)  # 85 의 아침 단계 — 07:06~07:48
HOURLY_LO, HOURLY_HI = 6, 48  # chat-gate 손 호출 분 — batch_gate 가 막는 정각 ±5분(55~05분)보다 넉넉히, 정각 예약 실행이 심은 행을 먼저 먹지 않게
EDGE_LO, EDGE_HI = 50 * 60, 58 * 60 + 30  # 72 · 73 의 시작 허용 구간(경계 직전 시(時)의 xx:50:00~xx:58:30, 초)
BEFORE_BOUNDARY, AFTER_BOUNDARY = 40, 20  # 첫 수락은 경계 40초 전, 둘째는 20초 뒤에 보낸다
WATCH_STOP = 3  # 73 에서 첫 보관 수락 뒤 "안 온다" 를 지켜보다 경계 몇 초 전에 멈추는지 — 08:00 예약 실행이 끼지 않게
EARLY_DEADLINE = (7, 57)  # 85: 이 시각이 지나면 07시대 관찰을 못 한다(08:00 예약 실행이 끼는 시각)
SCHEDULED_BY = (8, 3)  # 85: 08:00 예약 실행이 보내기를 기다리는 한계
CASE_LIMIT_NIGHT = 900  # 한 단계(60초 지켜보기 + 대조 + 앱 켜기) — 기본 420초를 넘는다
CASE_LIMIT_85 = 4500  # 07:06 부터 08:03 까지 기다리고 08:06 뒤 손 호출까지(최대 약 75분)
WINDOW = '밤 22:00~23:59'
NOTICE_ROW = ('kind', 'title', 'body', 'data')  # 보관 행에서 기록하는 칸(나머지는 심을 때 새로)
_FAILED = {}  # (묶음 폴더, 번호) → 배치를 부른 뒤 · 첫 수락을 보낸 뒤 fail 이던 결과. run_case 의 재시도가 같은 번호로 다시 부르면 이 결과를 돌려준다
_SENT = [0]  # 지금까지 손으로 chat-gate 를 부르거나 첫 수락을 보낸 횟수 — 가설 하나가 그 사이에 늘렸는지로 "되돌릴 수 없는 일을 했나" 를 안다


# ── 시각 창(순수 함수 — 가짜 시계로 시험) ────────────────────────────────────────────────────────

def _again(now, when):
    """batch_gate.refusal 과 같은 모양 — 다른 날이면 요일까지."""
    day = '' if when.date() == now.date() else f'{batch_gate.WEEKDAY_NAMES[when.weekday()]}요일 '
    return f'지금은 실행 금지 시간 — {day}{when:%H:%M} 에 다시'


def _next_open(now, is_open):
    t = now.replace(second=0, microsecond=0)
    for _ in range(8 * 24 * 60):
        t += timedelta(minutes=1)
        if is_open(t):
            return t
    raise ValueError('열린 분을 못 찾음')


def _hourly_open(t, hours):
    return t.hour in hours and HOURLY_LO <= t.minute <= HOURLY_HI


def hourly_refusal(now, hours):
    """서울 [now] 가 [hours] 시(時)의 hh:06~hh:48 분이면 None, 아니면 "지금은 실행 금지 시간 — HH:MM 에 다시"."""
    return None if _hourly_open(now, hours) else _again(now, _next_open(now, lambda t: _hourly_open(t, hours)))


def morning_refusal(now):
    """아침 단계(08:06~21:48 의 hh:06~hh:48) — 손으로 부른 chat-gate 가 정각 예약 실행과 겹치지 않고, 심은 행이 그 예약에 먼저 소비되지 않는다."""
    return hourly_refusal(now, DAY_HOURS)


def early_refusal(now):
    """85 의 아침 단계(07:06~07:48) — 조용한 시간이 아직 안 끝난 시각의 손 호출."""
    return hourly_refusal(now, EARLY_HOURS)


def _edge_open(t, hour):
    return t.hour == hour and EDGE_LO <= t.minute * 60 + t.second <= EDGE_HI


def edge_refusal(now, hour):
    """72 · 73 시작 허용: [hour] 시(時)의 xx:50:00~xx:58:30(경계는 그다음 정각). 아니면 "… HH:50 에 다시"."""
    if _edge_open(now, hour):
        return None
    return _again(now, _next_open(now, lambda t: t.second == 0 and _edge_open(t, hour)))


def night_step(now, state, hours=DAY_HOURS):
    """어느 단계인지 → ('night', None) | ('morning', None) | (None, 금지 문구).
    [state] 는 밤 단계가 남긴 {'night_date': 'YYYY-MM-DD', 'done': bool} 또는 None. **어제 밤(정확히 하루 전)의 미완 상태**만 아침 단계를 부른다 —
    그보다 오래된 상태는 버리고 새 밤 단계로 간다. 아침 창의 마지막 분이 지나면 그날 아침은 끝난 것이라 밤 단계 안내로 간다."""
    waiting = bool(state) and not state.get('done') and (now.date() - date.fromisoformat(state['night_date'])).days == 1
    said = hourly_refusal(now, hours)
    if waiting and not said:
        return 'morning', None
    if waiting and (now.hour, now.minute) <= (max(hours), HOURLY_HI):
        return None, said
    refused = td.night_refusal(now)
    return (None, refused) if refused else ('night', None)


def night_note(number):
    when = '07:06~07:48 사이' if number == '85' else '08:06 이후'
    return (f'1단계 끝 — 내일 {when} 같은 번호를 같은 --bundle 로 다시(상태 파일이 묶음 폴더 안). '
            '밤에 만든 보관 행은 08시 예약이 먹지 않게 지웠고, 아침 단계가 기록한 행을 다시 심는다')


def _no_rerun(number, case):
    """배치(손 호출 chat-gate)를 부른 뒤 또는 첫 수락을 보낸 뒤의 fail 은 기억해 두었다가, 같은 가설이 다시 불리면 앱도 계정도 안 만들고 그대로 돌려준다.
    다시 돌면 같은 시(時) 관문 · 시작 창이 막아 진짜 결과가 blocked 로 덮인다. 그 전의 fail · blocked 와 밤 단계의 fail 은 그대로 다시 돈다."""
    def wrapped(run, phone):
        key = (run.out, number)
        if key in _FAILED:
            return _FAILED.pop(key)
        before = _SENT[0]
        result = case(run, phone)
        if result[0] == 'fail' and _SENT[0] > before:
            _FAILED[key] = result
        return result
    return wrapped


def _batch(name):
    """area2._batch(관문 → gcloud)를 부르고 센다 — 관문에서 막히면(예외) 세지 않는다."""
    area2._batch(name)
    _SENT[0] += 1


def _sleep_until(target):
    while (left := (target - td.now_seoul()).total_seconds()) > 0:
        time.sleep(min(left, 5))


# ── 상태 파일 · 보관 행 ────────────────────────────────────────────────────────────────────────

def _state_path(run, number):
    return run.out / f'night_{number}.json'


def _read_state(run, number):
    path = _state_path(run, number)
    return json.loads(path.read_text(encoding='utf-8')) if path.exists() else None


def _write_state(run, number, state):
    _state_path(run, number).write_text(json.dumps(state, ensure_ascii=False, indent=1), encoding='utf-8')


def _held(run, *profile_ids):
    """그 사람들의 보관 행(들어온 순서)."""
    return [row for pid in profile_ids
            for row in _rows(run, f'pending_pushes?profile_id=eq.{pid}&select=id,kind,title,body,data&order=created_at')]


def _drop(run, *profile_ids):
    """이번 실행 계정들의 보관 행을 지운다 — 08시 예약 chat-gate 가 먹어 폰에 진짜 알림이 가지 않게. 못 지우면 사유 글, 지웠으면 ''."""
    area2._guard(run, *profile_ids)
    bad = [pid for pid in profile_ids
           if tools.rest(run.cfg, run.key, 'DELETE', f'pending_pushes?profile_id=eq.{pid}')[0] >= 300]
    return f'pending_pushes 행을 지우지 못함({bad}) — 08시 예약 실행이 먹을 수 있다' if bad else ''


def _keep(s, count, kind, route, receiver=None):
    """받는 사람의 보관 행이 정확히 [count] 개 · 모두 [kind] / [route] 인지 보고 내용을 [s.rows] 에 기록한다."""
    who = receiver or s.me
    rows = _held(s.run, who['id'])
    shape = [(r['kind'], (r['data'] or {}).get('route')) for r in rows]
    s.check.that(shape == [(kind, route)] * count, f'pending_pushes 의 {who["id"]} 행이 {shape}(기대 {kind}/{route} {count}개)')
    s.rows = [{k: r[k] for k in NOTICE_ROW} for r in rows]


def _no_row(s, who, kind):
    """[who] 에게 [kind] 보관 행이 없다 — 방금 화면에서 본 쪽은 보관 없이 버려진다."""
    rows = [r for r in _held(s.run, who['id']) if r['kind'] == kind]
    s.check.that(not rows, f'{who["id"]} 의 {kind} 보관 행이 {len(rows)}개(기대 0 — 방금 누른 쪽은 보관 없이 버림)')


def _quiet_on(s):
    status, body = _api(s.run, 'GET', '/cards/notification-settings', s.me['token'])
    if status != 200 or (body or {}).get('quiet_hours') is not True:
        raise Blocked(f'방해 금지(quiet_hours)가 켜져 있어야 밤 보관 · 예외를 볼 수 있다 — 지금 {status} {body}')


# ── 장면 ────────────────────────────────────────────────────────────────────────────────────────

class _Night(_Scene):
    """밤 장면 — area4_push._Scene(밤이라 낮 제한을 끈다) + 만든 계정 목록(보관 행을 지울 사람) + 기록할 보관 행."""

    def __init__(self, run, phone):
        super().__init__(run, phone, daytime=False)
        self.rows, self.involved = [], [self.me['id'], self.partner['id']]

    def person(self):
        person = area3_phone._person(self.run)
        self.involved.append(person['id'])
        return person


class _Morning(_Scene):
    """아침 장면 — 밤에 만든 받는 사람 계정으로 다시 로그인해 토큰을 되찾는다. 계정을 새로 만들지 않는다."""

    def __init__(self, run, phone, receiver):
        notify.ensure_delivery(phone.serial)  # 푸시 연결이 죽은 폰이면 아침 알림이 안 떠 "안 온다" 를 믿을 수 없다 — 다시 로그인하기 전에 점검
        self.run, self.phone, self.check, self.notes = run, phone, Check(), []
        self.me, self.partner, self.ready = receiver, None, False
        _app(self.check, phone(token_hash=run.link(receiver['email'])))
        if self.check.problems:
            return
        if not _wait_for(lambda: _rows(run, f"push_tokens?profile_id=eq.{receiver['id']}&select=token"), TOKEN_WAIT):
            raise Blocked(f'{TOKEN_WAIT}초 안에 기기 토큰이 서버에 안 올라옴 — 알림 권한 · FCM 확인')
        notify.background(phone.serial)
        self.ready = True


def _run_night(run, phone, act, regate=None, quiet=True, save=None, number=None):
    """밤 장면을 만들고 [act] 를 돌린다. 끝나면(예외여도) 만든 계정들의 보관 행을 지운다.
    [save] 가 있으면(두 단계 가설) 문제가 없을 때 상태 파일을 쓰고 blocked 로 끝낸다."""
    start = td.now_seoul()
    s = _Night(run, phone)
    try:
        if s.ready:
            said = regate(td.now_seoul()) if regate else None
            if said:  # 준비하는 사이 창을 벗어났으면 낮 결과가 된다
                raise Blocked(f'{WINDOW} 창을 벗어남 — {said}')
            if quiet:
                _quiet_on(s)
            want = act(s)
    finally:
        left = _drop(run, *s.involved)
    s.check.that(not left, left)
    if s.check.problems or save is None:
        return s.check.result('; '.join(s.notes))
    save(start, s, want)
    raise Blocked(night_note(number))


# ── 밤 단계 본문(상대 행동 → 받는 사람 0개 · 보관 행). 돌려주는 값 = 아침에 뜰 알림 [(제목, 본문)] ─────────────────────

def _n_accept(s):
    """15 · 84 · 85 — 상대가 R 의 카드를 수락."""
    card = factory.card(s.run, s.partner, s.me)
    before = s.before()
    factory.accept_card(s.run, s.partner, card)
    s.silent(before, only=lambda n: n.title == ACCEPT_TITLE)
    _keep(s, 1, 'acceptance_received', 'acceptances')
    return [(ACCEPT_TITLE, accept_body(s.nick))]


def _n_84(s):
    _n_accept(s)
    return []  # 아침에 스위치를 끄고 보내므로 아무것도 안 온다


def _n_match(s):
    """23 — R 이 먼저 수락한 쪽, 상대가 받은 수락을 수락."""
    card = factory.card(s.run, s.me, s.partner)
    factory.accept_card(s.run, s.me, card)  # 상대에게 "받은 수락" 보관이 생긴다(지운다) — 아래는 match_made 만 센다
    before = s.before()
    s.matched('상대가 받은 수락을 수락', factory.accept_back(s.run, s.partner, card))
    _one_match(s)
    s.silent(before, only=lambda n: n.title == MATCH_TITLE)
    _keep(s, 1, 'match_made', 'match')
    _no_row(s, s.partner, 'match_made')
    return [(MATCH_TITLE, _matched(s.nick))]


def _n_review(s):
    """52 — 추천으로 이어진 상대가 리뷰."""
    factory.link(s.run, s.partner, s.me)
    before = s.before()
    factory.review(s.run, s.partner, s.me)
    s.check.that(len(_reviews(s)) == 1, 'friend_reviews 가 1행이 아님')
    s.silent(before, only=lambda n: n.title == REVIEW_TITLE)
    _keep(s, 1, 'new_friend_review', 'friend_reviews')
    return [(REVIEW_TITLE, f'{s.nick} 님이 리뷰를 남겼어요')]


def _n_two_accepts(s):
    """83 — 두 사람의 수락 → 한 알림으로 묶여 온다."""
    second = s.person()
    cards = [factory.card(s.run, p, s.me) for p in (s.partner, second)]
    before = s.before()
    for person, card in zip((s.partner, second), cards):
        factory.accept_card(s.run, person, card)
    s.silent(before, only=lambda n: n.title == ACCEPT_TITLE)
    _keep(s, 2, 'acceptance_received', 'acceptances')
    return [(ACCEPT_TITLE, '밤사이 2명이 나를 수락했어요')]


def _n_public(s):
    """86 — R 이 먼저 신뢰 수락, 밤에 상대가 수락해 둘 다 통과."""
    match_id = factory.match(s.run, s.me, s.partner)
    factory.trust(s.run, s.me, match_id)
    before = s.before()
    factory.trust(s.run, s.partner, match_id)
    s.proof(before, s.nick, TRUST_BODY)  # 상대의 신뢰 수락은 새 메시지로 밤에도 온다 — 알림 길이 살아 있다는 증거를 겸한다
    s.silent(before, only=lambda n: n.title == PUBLIC_TITLE, control=None)
    rows = _rows(s.run, f'matches?id=eq.{match_id}&select=trust_passed_at')
    s.check.that(rows and rows[0].get('trust_passed_at'), f'trust_passed_at {rows}(찍혀야 함)')
    _keep(s, 1, 'match_made', 'chat')
    _no_row(s, s.partner, 'match_made')
    return [(PUBLIC_TITLE, _public(s.nick))]


def _n_two_reviews(s):
    """87 — 추천 연결된 두 사람의 리뷰 → 한 알림으로 묶여 온다. R 이 추천인이다(referee_id 가 기본키)."""
    second = s.person()
    for person in (s.partner, second):
        factory.link(s.run, s.me, person)
    before = s.before()
    for person in (s.partner, second):
        factory.review(s.run, person, s.me)
    s.check.that(len(_reviews(s)) == 2, 'friend_reviews 가 2행이 아님')
    s.silent(before, only=lambda n: n.title == REVIEW_TITLE)
    _keep(s, 2, 'new_friend_review', 'friend_reviews')
    return [(REVIEW_TITLE, '밤사이 리뷰 2개가 도착했어요')]


def _n_signups(s):
    """88 — R 의 추천 코드를 새 계정 둘이 입력 → 묶지 않고 한 건씩."""
    code = area4_set2._code(s.run, s.me['id'])
    friends = []
    for _ in range(2):
        friend = s.run.account('ideal_note')
        s.involved.append(friend['id'])
        friends.append((friend, _one(s.run, f"profiles?id=eq.{friend['id']}&select=nickname").get('nickname')))
    if not all(nickname for _, nickname in friends):
        raise Blocked('가입한 계정의 닉네임을 못 읽음')
    before = s.before()
    for friend, _ in friends:
        factory.redeem(s.run, friend, code)
    s.silent(before, only=lambda n: n.title == FRIEND_TITLE)
    _keep(s, 2, 'new_friend_review', 'friend_review_write')
    return [(FRIEND_TITLE, f'{nickname} 님이 가입했어요, 리뷰를 남겨 주세요') for _, nickname in friends]


NIGHT = {'15': _n_accept, '23': _n_match, '52': _n_review, '83': _n_two_accepts, '84': _n_84, '85': _n_accept,
         '86': _n_public, '87': _n_two_reviews, '88': _n_signups}


# ── 단일 단계: 16 · 33 ──────────────────────────────────────────────────────────────────────────

def _n_quiet_off(s):
    """16 — 방해 금지를 끄면 밤에도 받은 수락이 바로 온다(보관 없음)."""
    factory.switches(s.run, s.me, quiet_hours=False)
    card = factory.card(s.run, s.partner, s.me)
    before = s.before()
    factory.accept_card(s.run, s.partner, card)
    s.arrives(before, ACCEPT_TITLE, accept_body(s.nick), once=True)
    s.check.that(not _held(s.run, s.me['id']), 'pending_pushes 에 행이 생김 — 방해 금지를 껐으면 보관 없이 바로 와야 함')


def _n_message(s):
    """33 — 방해 금지가 켜져 있어도 새 메시지는 밤에 온다."""
    match_id = factory.match(s.run, s.me, s.partner)
    text = f'E2E-33-{area2._new_id()[:6]}'
    before = s.before()
    factory.send(s.run, s.partner, match_id, text)
    s.arrives(before, s.nick, text, once=True)
    s.check.that(not _held(s.run, s.me['id']), 'pending_pushes 에 행이 생김 — 새 메시지는 보관 대상이 아님')


def _gated(gate, body):
    """창 밖이면 권한 · 계정을 건드리기 전에 Blocked."""
    def case(run, phone):
        said = gate(td.now_seoul())
        if said:
            raise Blocked(said)
        return _permitted(body)(run, phone)
    return case


def _single(act, quiet=True):
    return _gated(td.night_refusal, lambda run, phone: _run_night(run, phone, act, regate=td.night_refusal, quiet=quiet))


# ── 두 단계 ─────────────────────────────────────────────────────────────────────────────────────

def _two_stage(number, act, hours=DAY_HOURS):
    def case(run, phone):
        state = _read_state(run, number)
        step, said = night_step(td.now_seoul(), state, hours)
        if said:
            raise Blocked(said)
        if step == 'morning':
            said = batch_gate.refusal('chat-gate', td.now_seoul(), batch_gate._ran())  # 같은 시(時)에 이미 손으로 불렀으면 심기 전에 멈춘다
            if said:
                raise Blocked(said)
            return _permitted(lambda run, phone: _morning(run, phone, state, number))(run, phone)

        def save(start, s, want):
            _write_state(run, number, {'night_date': start.date().isoformat(), 'receiver': {'id': s.me['id'], 'email': s.me['email']},
                                       'rows': s.rows, 'want': [list(w) for w in want]})
        return _permitted(lambda run, phone: _run_night(run, phone, act, regate=td.night_refusal, save=save, number=number))(run, phone)
    return _no_rerun(number, case)


# ── 아침 단계 ───────────────────────────────────────────────────────────────────────────────────

def _morning(run, phone, state, number):
    receiver = state['receiver']
    area2._guard(run, receiver['id'])  # 상태 파일이 남의 계정을 가리키면 아무것도 쓰지 않는다
    m = _Morning(run, phone, {**receiver, 'token': run.sign_in(receiver['email'])})
    try:
        if m.ready:
            _judge(m, state, number)
    finally:
        left = _drop(run, receiver['id'])  # 심은 행이 남았으면(앵커 없음 · 실패) 08시 예약이 먹지 않게
    m.check.that(not left, left)
    if not m.check.problems:
        _write_state(run, number, {**state, 'done': True})
    return m.check.result('; '.join(m.notes))


def _plant(m, rows):
    """기록한 행을 새 id 로 심는다 — 이 호출 바로 뒤에 손 호출이 와야 한다(사이에 다른 요청을 끼우지 않는다)."""
    area2._insert(m.run, 'pending_pushes', [{'id': area2._new_id(), 'profile_id': m.me['id'], **row} for row in rows], m.me['id'])


def _gone(m):
    if not _wait_for(lambda: not _held(m.run, m.me['id']), CARD_WAIT):
        raise Blocked(f'chat-gate 를 불렀으나 {CARD_WAIT}초 안에 보관함 행이 안 사라짐 — 배치가 안 돈 것 같아 알림 판정을 못 함')


def _exactly(m, before, want):
    """[want] 의 제목을 가진 새 알림이 정확히 [want] 만큼(문구까지) 왔고, 도착 뒤 SETTLE 초 동안 더 오지 않는다."""
    titles = {title for title, _ in want}
    new = notify.wait_new(m.phone.serial, before, count=len(want), seconds=NOTICE_WAIT)
    more = notify.expect_none(m.phone.serial, [*before, *new], seconds=SETTLE)
    mine = [n for n in [*new, *more] if n.title in titles]
    m.check.that(sorted((n.title, n.text) for n in mine) == sorted(want),
                 f'아침 알림이 기대와 다름 — 온 것: {notice_memo(mine)} · 기대: {sorted(want)} (새 알림 전부: {notice_memo([*new, *more])})')


def _judge(m, state, number):
    rows, want = state['rows'], [tuple(w) for w in state['want']]
    titles = {row['title'] for row in rows}
    before = m.before()
    if number == '84':
        factory.switches(m.run, m.me, acceptance_received=False)  # 보관 알림은 보낼 때 스위치를 다시 본다
    if number == '85':
        _early(m, rows, want, titles, before)
        return
    _plant(m, rows)
    _batch('chat-gate')
    _gone(m)
    if number == '84':
        m.silent(before, only=lambda n: n.title in titles)
    else:
        _exactly(m, before, want)
    m.notes.append('손으로 chat-gate(관문 통과). 배치 응답의 deferred_sent 는 스케줄러 호출이라 못 읽음 — 보관 행 · 알림창으로 확인')


def _anchor(m):
    """배치가 돌았다는 증거 — 양쪽이 신뢰 수락했지만 도장이 없는 새 매칭. chat-gate 가 돌면 trust_passed_at 을 찍는다."""
    x, y = area3_phone._person(m.run), area3_phone._person(m.run)
    match_id = factory.match(m.run, x, y)
    area3._patch(m.run, f'match_participants?match_id=eq.{match_id}', {'trust_response': 'accept', 'responded_at': area2._now().isoformat()})
    return match_id


def _stamped(run, match_id):
    return _one(run, f'matches?id=eq.{match_id}&select=trust_passed_at').get('trust_passed_at')


def _at(day, hour_minute):
    return day.replace(hour=hour_minute[0], minute=hour_minute[1], second=0, microsecond=0)


def _early(m, rows, want, titles, before):
    """85 — 07시대 손 호출은 보관 알림을 그대로 둔다 → 08:00 예약 실행이 보낸다."""
    now = td.now_seoul()
    if now >= _at(now, EARLY_DEADLINE):
        raise Blocked(f'준비가 길어 {EARLY_DEADLINE[0]:02d}:{EARLY_DEADLINE[1]:02d} 을 넘음 — 08:00 예약 실행이 끼어 07시대를 못 봄. 07:06~07:48 에 다시')
    anchor = _anchor(m)
    _plant(m, rows)
    _batch('chat-gate')
    if not _wait_for(lambda: _stamped(m.run, anchor), CARD_WAIT):
        raise Blocked(f'chat-gate 를 불렀으나 {CARD_WAIT}초 안에 앵커(새 매칭의 trust_passed_at)가 안 찍힘 — 배치가 안 돈 것 같아 "그대로 둔다" 를 판정 못 함')
    held = _held(m.run, m.me['id'])
    m.check.that(len(held) == len(rows), f'07시대 배치가 보관 행을 건드림 — {len(held)}행(기대 그대로 {len(rows)}행)')
    watch = min(NOTICE_WAIT, max(1, int((_at(now, EARLY_DEADLINE) + timedelta(minutes=1) - td.now_seoul()).total_seconds())))  # 08:00 예약 실행이 끼기 전에 멈춘다
    seen = [n for n in notify.expect_none(m.phone.serial, before, seconds=watch) if n.title in titles]
    m.check.that(not seen, f'07시대 배치가 보관 알림을 보냄: {notice_memo(seen)}')
    if m.check.problems:
        return
    deadline = _at(now, SCHEDULED_BY)
    while _held(m.run, m.me['id']) and td.now_seoul() < deadline:
        time.sleep(10)
    how = '08:00 예약 chat-gate 가 보냄'
    if _held(m.run, m.me['id']):
        while morning_refusal(td.now_seoul()):  # 정각 ±5분을 피해 08:06 까지
            time.sleep(15)
        _batch('chat-gate')
        _gone(m)
        how = '08:00 예약 실행이 08:03 까지 안 보내 08:06 뒤 손으로 chat-gate 를 불렀다(손으로 불러 보내졌다 — 예약 실행이 안 보냄, 확인 필요)'
    _exactly(m, before, want)
    m.notes.append(how)


# ── 경계 시각: 72 · 73 ──────────────────────────────────────────────────────────────────────────

def _edge(number, hour, first_arrives):
    """[hour] 시(時) 59분 → 다음 정각이 방해 금지 경계. 72(21→22): 첫 수락은 오고 둘째는 보관. 73(7→8): 첫 수락은 보관, 둘째는 바로 옴."""
    def act(s):
        day = td.now_seoul()
        boundary = day.replace(hour=hour + 1, minute=0, second=0, microsecond=0)
        first_at, second_at = boundary - timedelta(seconds=BEFORE_BOUNDARY), boundary + timedelta(seconds=AFTER_BOUNDARY)
        if td.now_seoul() >= first_at:
            raise Blocked(f'준비가 길어져 {first_at:%H:%M:%S} 을 넘음 — {hour:02d}:50~{hour:02d}:57 에 시작')
        second = s.person()
        card_1, card_2 = factory.card(s.run, s.partner, s.me), factory.card(s.run, second, s.me)
        before = s.before()
        _sleep_until(first_at)
        sent_1 = td.now_seoul()
        _SENT[0] += 1  # 첫 수락을 보낸다 — 이 뒤의 fail 은 다시 돌면 시작 창 밖이라 blocked 로 덮인다
        factory.accept_card(s.run, s.partner, card_1)
        done_1 = td.now_seoul()
        s.notes.append(f'첫 수락 {sent_1:%H:%M:%S}~{done_1:%H:%M:%S}')
        if done_1 >= boundary:
            raise Blocked(f'경계를 못 맞춤 — 첫 수락이 {sent_1:%H:%M:%S}~{done_1:%H:%M:%S} 에 끝나 {boundary:%H:%M:%S} 를 넘음(서버 시계는 PC 와 다를 수 있다)')
        if first_arrives:
            s.arrives(before, ACCEPT_TITLE, accept_body(s.nick), once=True)
            s.check.that(not _held(s.run, s.me['id']), f'{hour:02d}:59 의 수락이 보관됨 — 경계 전이라 바로 와야 함')
        else:
            _keep(s, 1, 'acceptance_received', 'acceptances')
            wait = max(1, int((boundary - td.now_seoul()).total_seconds()) - WATCH_STOP)  # 08:00 예약 실행이 끼지 않게 그 전에 멈춘다
            seen = [n for n in notify.expect_none(s.phone.serial, before, seconds=wait) if n.title == ACCEPT_TITLE]
            s.check.that(not seen, f'{hour:02d}:59 의 수락 알림이 경계 전에 옴(보관해야 함): {notice_memo(seen)}')
        _sleep_until(second_at)
        before_2 = s.before()
        sent_2 = td.now_seoul()
        if sent_2 < boundary:
            raise Blocked(f'경계를 못 맞춤 — 둘째 수락이 {sent_2:%H:%M:%S} 에 나감(경계 {boundary:%H:%M:%S} 전)')
        factory.accept_card(s.run, second, card_2)
        s.notes.append(f'둘째 수락 {sent_2:%H:%M:%S}~{td.now_seoul():%H:%M:%S}')
        if first_arrives:
            s.silent(before_2, only=lambda n: n.title == ACCEPT_TITLE)
            _keep(s, 1, 'acceptance_received', 'acceptances')
        else:
            s.arrives(before_2, ACCEPT_TITLE, accept_body(second['nickname']), once=True)
            known = {n.key for n in before}
            late = [n for n in notify.read_notifications(s.phone.serial)
                    if n.key not in known and (n.title, n.text) == (ACCEPT_TITLE, accept_body(s.nick))]
            if late:
                s.notes.append('08:00 예약 실행이 첫 번째 보관분도 따로 보냄 — 문구가 달라 판정에서 뺌')
    return _no_rerun(number, _gated(lambda now: edge_refusal(now, hour), lambda run, phone: _run_night(run, phone, act)))


# ── 등록 ────────────────────────────────────────────────────────────────────────────────────────

_CASES = {
    '15': _two_stage('15', _n_accept), '16': _single(_n_quiet_off, quiet=False), '23': _two_stage('23', _n_match),
    '33': _single(_n_message), '52': _two_stage('52', _n_review), '72': _edge('72', 21, True), '73': _edge('73', 7, False),
    '83': _two_stage('83', _n_two_accepts), '84': _two_stage('84', _n_84), '85': _two_stage('85', _n_accept, EARLY_HOURS),
    '86': _two_stage('86', _n_public), '87': _two_stage('87', _n_two_reviews), '88': _two_stage('88', _n_signups),
}
PHONE = {f'E-PUSH-{number}': case for number, case in _CASES.items()}
WITH_NIGHT_STAGE = [f'E-PUSH-{n}' for n in ('15', '16', '23', '33', '52', '83', '84', '85', '86', '87', '88')]

tools.CASE_LIMITS.update({case: CASE_LIMIT_NIGHT for case in PHONE})
tools.CASE_LIMITS['E-PUSH-85'] = CASE_LIMIT_85

area1.PHONE.update(PHONE)
area1.BUNDLES['area4-push-night'] = list(PHONE)
area1.BUNDLES['area4-push-night-a'] = WITH_NIGHT_STAGE
area1.BUNDLES['area4-push-edge'] = ['E-PUSH-72', 'E-PUSH-73']
