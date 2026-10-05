"""영역 2 기기 · 시각 가설 13개 — 배치 + 알림 8, 시계 5(묶음 area2-time-device). 기대값은 바탕화면 시나리오가 아니라 지금 코드 기준이다.
앱 쪽은 frontend/integration_test/area2_d.dart 의 같은 번호(알림만 보는 가설은 E-ONB-61 처럼 홈까지만 켜 두는 앱 가설을 그대로 쓴다).

  배치 + 알림   E-CARD-01 · 03 · 13 · 17 · 18 · 19 · 20 · E-HOME-29
  시계          E-HOME-23 · 24 · 25 · 26 · E-CARD-44(밤 → 아침 2단계)

배치는 **언제나 `area2._batch` 로** — 실행 금지 시각이면 gcloud 를 안 부르고 blocked. 서버 시계는 못 옮기므로 시각 가설은
(1) DB 의 시각 칸(시험대학 `card_opens_at` · 이번 실행 계정의 카드 `issued_at`/`expires_at`)을 옮기거나 (2) 가설 코드가 스스로
"이 시각에만" 돈다(아니면 `Blocked('지금은 실행 금지 시간 — … 에 다시')`) 거나 (3) 앱 시계 자리(`homeNowProvider`)를 바꿔 끼운다.
쓰기는 이번 실행이 만든 계정 id 와 시험대학 행 · 시험 지역(`e2e`) 설정 행에만 — 시험대학 · 지역 행은 끝나면(예외여도) 되돌린다.

돌릴 때: A폰(`--device A`)용 `area2-time-device-a`, B에뮬(`--device B`)용 `area2-time-device-b`, 둘을 합친 `area2-time-device`.
시각 창 밖이면 그 가설은 blocked 이고 메모에 "언제 다시" 가 나온다(Windows 예약 실행 시각은 보고서 분류표).
"""

import json
import re
import subprocess
from contextlib import contextmanager
from datetime import date, datetime, timedelta

from e2e import area1, area2, batch_gate, emu, notify, tools
from e2e.area1 import SEOUL, Check, _api, _app, _one, _patch, _rows, _signed_in, _test_university
from e2e.area2 import _ONCE, _candidates, _card, _guard, _insert, _new_id, _person, _set_status
from e2e.area2_phone3 import CARD_BODY, CARD_TITLE, EVERY_DAY, LADDER_ZERO, _region_of, _slow, _wait_for, region_set
from e2e.tools import Blocked

WEEKDAY_NAMES = '월화수목금토일'
CARD_WAIT = 90  # 배치 뒤 카드 행이 DB 에 보일 때까지(초) — 스케줄러 호출은 끝을 알려 주지 않는다
NOTICE_WAIT = 30  # 카드가 생긴 뒤 알림이 폰에 뜰 때까지(시나리오 E-CARD-01 "30초 안")
ABSENCE_WAIT = 45  # "안 온다" 를 지켜보는 시간
QUIET_WAIT = 60  # 알림을 껐거나 밤이라 "안 온다" 를 지켜보는 시간(시나리오 E-CARD-18 "60초 알림 0")
LEAD_MIN = 60  # 시계 가설이 앱을 켠 뒤 기준 시각까지 남아 있어야 하는 시간(초) — 모자라면 앱이 대기 화면을 못 본다
APP_WAIT = 900  # 앱이 PC 일(배치)을 기다린 뒤 마저 도는 시간(초) — Run.phone 기본 180초보다 길게(E-CARD-13)
SETTLE = 10  # 알림이 온 뒤 같은 알림이 한 번 더 오는지 보는 시간
INTERVAL_MIN = 55  # 서버 요청 간격 "1분 미만" 의 기계 오차(초)
OPEN_LATE = 125  # 여는 시각(07:00:00) 뒤 09b 가 보이기까지 허용 — 시나리오 "07:02:00 사이" + 시계 오차
FLIP_LATE = 65  # 자정 뒤 D-숫자가 바뀌기까지 허용 — 시나리오 "00:01 사이" + 시계 오차
NIGHT_TITLE = '나를 수락한 사람이 있어요'  # backend/app/cards/router.py decide_card


def now_seoul():
    return datetime.now(SEOUL)


# ── 시각 창(순수 함수 — 가짜 시계로 시험) ────────────────────────────────────────────────────────────

def _again(now, again, weekday=None, not_weekday=None):
    """[now] 뒤 처음 오는 [again](자정부터 분) 시각 — [weekday] 요일만(0=월), [not_weekday] 는 건너뛴다."""
    base = now.replace(hour=again // 60, minute=again % 60, second=0, microsecond=0)
    for days in range(15):
        target = base + timedelta(days=days)
        if target > now and weekday in (None, target.weekday()) and not_weekday != target.weekday():
            return target
    raise ValueError('다음 시각을 못 찾음')


def refuse_outside(now, lo, hi, again, weekday=None, not_weekday=None):
    """서울 시각 [now] 가 [lo, hi) 분(자정부터)이고 요일 조건에 맞으면 None, 아니면 "지금은 실행 금지 시간 — HH:MM 에 다시"
    (날이 다르면 요일까지, batch_gate.refusal 과 같은 모양)."""
    minutes = now.hour * 60 + now.minute
    if lo <= minutes < hi and weekday in (None, now.weekday()) and not_weekday != now.weekday():
        return None
    target = _again(now, again, weekday, not_weekday)
    when = f'{target:%H:%M}' if target.date() == now.date() else f'{WEEKDAY_NAMES[target.weekday()]}요일 {target:%H:%M}'
    return f'지금은 실행 금지 시간 — {when} 에 다시'


def night_refusal(now, skip_monday=False):
    """밤 단계(E-CARD-17 · 44 1단계) — 서울 22:00~23:59 에만. [skip_monday] 는 daily-cards 를 부르는 가설용(월요일은 종일 금지)."""
    return refuse_outside(now, 22 * 60, 24 * 60, 22 * 60, not_weekday=0 if skip_monday else None)


def monday_morning_refusal(now):
    """E-HOME-24 — 월요일 06:40~06:58 에 시작해야 07:00 전에 앱이 대기 화면에 닿는다(예약은 06:50 쯤)."""
    return refuse_outside(now, 6 * 60 + 40, 6 * 60 + 59, 6 * 60 + 50, weekday=0)


def midnight_refusal(now):
    """E-HOME-25 — 23:40~23:58 에 시작해야 자정 전에 앱이 D-숫자를 그린다(예약은 23:50 쯤)."""
    return refuse_outside(now, 23 * 60 + 40, 23 * 60 + 59, 23 * 60 + 50)


def card44_step(now, state):
    """E-CARD-44 가 어느 단계인지 → ('night', None) | ('morning', None) | (None, 금지 문구).
    [state] 는 1단계가 남긴 {'night_date': 'YYYY-MM-DD', 'done': bool} 또는 None. 어제 밤(정확히 하루 전)의 미완 상태만 아침 단계를 부른다 —
    그보다 오래되면 08시 예약 배치가 보낸 알림이 이미 사라졌을 수 있어 새로 1단계부터 한다."""
    waiting = state and not state.get('done') and (now.date() - date.fromisoformat(state['night_date'])).days == 1
    morning = refuse_outside(now, 8 * 60 + 10, 21 * 60 + 50, 8 * 60 + 10)
    if waiting and not morning:
        return 'morning', None
    if waiting and now.hour * 60 + now.minute < 8 * 60 + 10:
        return None, morning
    night = night_refusal(now)
    return (None, night) if night else ('night', None)


def past_monday(now):
    """지난 월요일 07:00(서울) — [now] 보다 1시간 넘게 앞. 오늘이 월요일 07:00 직후여도 "지난" 값이 되게 한 주를 뺀다.
    universities_card_opens_monday_0700 check(월요일 07:00 서울만)를 지키는 값."""
    monday = (now - timedelta(days=now.weekday())).replace(hour=7, minute=0, second=0, microsecond=0)
    return monday if monday <= now - timedelta(hours=1) else monday - timedelta(days=7)


def future_monday(now, min_days=1):
    """서울 달력으로 [min_days] 일 이상 뒤의 첫 월요일 07:00 — 서버 시계로 확실히 "아직 안 열렸다"."""
    day = (now + timedelta(days=min_days)).replace(hour=7, minute=0, second=0, microsecond=0)
    return day + timedelta(days=(7 - day.weekday()) % 7)


def epoch_ms(moment):
    return int(moment.timestamp() * 1000)


def app_timeout(now, end):
    """앱이 [end] 까지 서 있는 가설에서 PC 가 앱 답을 기다리는 시간(초) — 마감까지 + 2분. 고정 값이면 일찍 시작한 날 PC 가 먼저 포기한다."""
    return max(0, int((end - now).total_seconds())) + 120


_GRANTED = re.compile(r'android\.permission\.POST_NOTIFICATIONS: granted=(true|false)')


def notifications_granted(dump):
    """`dumpsys package <패키지>` 글에서 알림 권한이 주어졌는지 — 줄이 없으면 None. 여러 번 나오면 마지막(런타임 권한 절)."""
    found = _GRANTED.findall(dump or '')
    return found[-1] == 'true' if found else None


# ── 기기 · 서버 도우미 ───────────────────────────────────────────────────────────────────────────────

def clock_skew(serial):
    """기기 시계 − PC 시계(초). 기기를 못 읽으면 0 — 시계 가설은 앱이 말한 시각을 이 값만큼 고쳐 판정한다."""
    if not serial:
        return 0
    try:
        device = emu.epoch(serial)
    except (ValueError, subprocess.CalledProcessError, OSError):
        return 0
    return device - now_seoul().timestamp() if device else 0


def device_ms(moment, skew):
    """PC 시각 [moment] 를 기기 시계(ms)로 — 앱이 자기 시계로 마감을 재게."""
    return epoch_ms(moment) + round(skew * 1000)


def require_revoked(serial):
    """`pm revoke` 가 정말 먹었는지 — 안 먹었는데 "알림이 왔다" 를 서버 결함으로 세지 않게."""
    state = notifications_granted(tools.adb(serial, 'shell', 'dumpsys', 'package', tools.PACKAGE, check=False))
    if state is not False:
        raise Blocked('알림 권한을 못 뺏음(dumpsys package 에 POST_NOTIFICATIONS granted=false 가 없음) — 안드로이드 13 이상 폰인가')


@contextmanager
def _permitted(serial):
    """알림 권한을 미리 주고(권한 창이 앱을 가리지 않게), 끝나면(예외여도) 되돌린다."""
    notify.grant_notifications(serial)
    try:
        yield
    finally:
        notify.revoke_notifications(serial)


def _pair(run):
    """A(남) · B(여) — 서로 후보. 둘 다 이번 실행이 만든 계정."""
    return _person(run, 'male'), _person(run, 'female')


def _every_day(run, owner):
    """시험 지역(`e2e`) 설정 행을 매일 지급으로 — 끝나면 원래 값. 지역이 `e2e` 가 아니면 Blocked."""
    return region_set(run, _region_of(run, owner), issue_weekdays=EVERY_DAY, **LADDER_ZERO)


def _token_up(run, account):
    """기기 토큰이 서버에 올라와야 배치가 보낸 알림이 이 기기에 닿는다."""
    if not _wait_for(lambda: _rows(run, f"push_tokens?profile_id=eq.{account['id']}&select=token"), 30):
        raise Blocked('30초 안에 기기 토큰이 서버에 안 올라옴 — 알림 권한 · FCM 확인')


def _ready(run, phone, account):
    """토큰이 올라온 뒤 알림창을 읽어 둔다 — 앞에 남은 알림과 섞이지 않게 새로 생긴 것만 본다."""
    _token_up(run, account)
    return notify.read_notifications(phone.serial)


def _daily_rows(run, owner):
    return _rows(run, f"daily_cards?owner_id=eq.{owner['id']}&source=eq.daily&select=id,issued_at,expires_at")


def require_daily_cards_open():
    """daily-cards 를 부르는 가설은 시작에서 — 월요일 · 00:00~07:10 이면 계정 · 앱을 만들기 전에 Blocked(`_batch` 관문은 한참 뒤에야 걸린다)."""
    said = batch_gate.refusal('daily-cards', now_seoul())
    if said:
        raise Blocked(said)


CONTROL_AXIS = 7  # 대조군의 문장 임베딩 축 — 대상 쌍(축 0)과 다른 축
CONTROL_MISSED = '대조군은 카드를 받았는데 대상은 못 받음'


def _control(run, like):
    """대조군 — 대상([like] 성별)과 같은 성별이라 대상의 후보 풀에 안 끼고, 반대 성별 후보가 있어 같은 배치에서 카드를 받는다.
    이 계정에게 가는 알림은 다른 기기(토큰 없음)라 폰 알림창을 흔들지 않는다."""
    return _person(run, like, embedding=CONTROL_AXIS)


def _issue(check, run, owner, have=0, control=None, control_have=0, anchored=False):
    """배치(관문 통과 후 gcloud) → [owner] 의 무료 카드가 [have] 장보다 늘 때까지(응답 본문은 못 읽는다). 늘면 True.
    안 늘면: 같은 배치가 돌았다는 증거 — [control] 이 [control_have] 장보다 늘었거나 [anchored] — 가 있으면 fail 로 적고 False,
    없으면 느린 배치와 결함을 못 가려 Blocked."""
    area2._batch('daily-cards')
    got = _wait_for(lambda: len(_daily_rows(run, owner)) > have, CARD_WAIT)
    if not got:
        said = f'배치는 불렸으나 {CARD_WAIT}초 안에 카드가 안 보임(daily_cards {len(_daily_rows(run, owner))}행)'
        if control is not None and len(_daily_rows(run, control)) > control_have:
            anchored, said = True, f'{CONTROL_MISSED} — {said}'
        if not anchored:
            raise Blocked(f'{said} — 느린 배치인지 결함인지 구분 못 함')
        check.that(False, said)
    return got


def _one_notice(check, serial, before, title=CARD_TITLE, text=CARD_BODY):
    """[NOTICE_WAIT] 초 안에 [title] / [text] 알림이 오고, 그 뒤 [SETTLE] 초 동안 다른 새 알림이 더 없다 — 새 알림이 정확히 1건."""
    new = notify.wait_new(serial, before, seconds=NOTICE_WAIT)
    if not [n for n in new if (n.title, n.text) == (title, text)]:
        check.that(False, f'{NOTICE_WAIT}초 안에 알림 "{title} / {text}" 없음(새 알림 {len(new)}건)')
        return
    new += notify.expect_none(serial, [*before, *new], seconds=SETTLE)
    check.that(len(new) == 1, f'새 알림 {len(new)}건(기대 1건): {[n.title for n in new]}')


def _expire(run, owner):
    """[owner] 의 카드를 만료시킨다 — 같은 날 두 번째 배치가 "오늘 이미 받은 사람" 으로 건너뛰지 않게 지급 시각도 이틀 전으로."""
    _guard(run, owner['id'])
    now = area2._now()
    _patch(run, f"daily_cards?owner_id=eq.{owner['id']}",
           {'issued_at': (now - timedelta(days=2)).isoformat(), 'expires_at': (now - timedelta(hours=1)).isoformat()})


def set_opens_at(run, school, value):
    _patch(run, f'universities?id=eq.{school}', {'card_opens_at': value.isoformat()})


OPENS_FILE = 'opens_at_original.json'  # 패치하기 전에 원래 값을 적어 둔다 — PC 가 강제로 꺼져 원복이 안 돼도 다음 실행이 되돌린다


def _restore_left_over(run, school):
    """앞 실행이 비정상 종료해 파일이 남았으면 그 값으로 먼저 되돌린다 — 안 그러면 다음 실행의 "원래 값" 이 닫아 둔 값으로 오염된다.
    파일의 학교가 지금 시험대학([school])이 아니면 남의 학교를 쓰지 않고 멈춘다(파일은 사람이 확인할 때까지 남긴다)."""
    path = run.out / OPENS_FILE
    if path.exists():
        saved = json.loads(path.read_text(encoding='utf-8'))
        if saved['school'] != school:
            raise Blocked('앞 실행이 남긴 원복 파일의 학교가 지금 시험대학과 다름 — 확인 후 파일을 지우고 다시')
        _patch(run, f'universities?id=eq.{school}', {'card_opens_at': saved['original']})
        path.unlink()


@contextmanager
def opens_at_set(run, value):
    """시험대학 행의 첫 카드 여는 시각을 [value](월요일 07:00 서울)로 — 끝나면(예외여도) 처음 값으로. 학교 id 를 돌려준다.
    universities_card_opens_monday_0700 check 가 월요일 07:00 서울만 받는다(20260928050000) — 과거 월요일도 된다."""
    school = _test_university(run)
    if not school:
        raise Blocked('시험대학 행을 못 찾음')
    _restore_left_over(run, school)
    original = _one(run, f'universities?id=eq.{school}&select=card_opens_at').get('card_opens_at')
    (run.out / OPENS_FILE).write_text(json.dumps({'school': school, 'original': original}), encoding='utf-8')
    set_opens_at(run, school, value)
    try:
        yield school
    finally:  # 못 되돌리면 이 시험대학이 계속 "안 열린 학교" 로 남는다 — 가리지 않고 Blocked 로 알리고 파일도 남긴다
        _patch(run, f'universities?id=eq.{school}', {'card_opens_at': original})
        (run.out / OPENS_FILE).unlink()


# ── 배치 + 알림 ─────────────────────────────────────────────────────────────────────────────────────

def p_card_01(run, phone):
    """홈에서 앱을 뒤로 → 배치 → A 카드 딱 1장(source=daily) + 30초 안에 알림 1건(제목 · 본문 일치)."""
    require_daily_cards_open()
    notify.ensure_delivery(phone.serial)  # 푸시 연결이 죽은 폰은 FCM 200 인데도 안 떠서 "온다" 는 헛fail, "안 온다" 는 헛통과 — 계정을 만들기 전에 되살린다(또는 blocked)
    check = Check()
    a, b = _pair(run)
    control = _control(run, 'male')
    with _permitted(phone.serial), _every_day(run, a):
        _app(check, phone(token_hash=run.link(a['email'])))
        before = _ready(run, phone, a)
        notify.background(phone.serial)  # 앱이 앞에 있으면 배너가 안 뜬다(E-CARD-03)
        if _issue(check, run, a, control=control):
            _one_notice(check, phone.serial, before)
    check.that(len(_daily_rows(run, a)) == 1, f'A 카드가 {len(_daily_rows(run, a))}장(기대 1)')
    return check.result('응답의 issued 개수는 스케줄러 호출이라 못 읽음 — A 의 daily_cards 행으로 확인')


def p_card_17(run, phone):
    """방해 금지 켠 채(기본) 22:00~23:59 에 배치 → 카드 도착 알림은 방해 금지 예외라 그래도 온다(push.py _QUIET_HOURS_EXEMPT)."""
    said = night_refusal(now_seoul(), skip_monday=True)
    if said:
        raise Blocked(said)
    notify.ensure_delivery(phone.serial)  # 푸시 연결이 죽은 폰은 FCM 200 인데도 안 떠서 "온다" 는 헛fail, "안 온다" 는 헛통과 — 계정을 만들기 전에 되살린다(또는 blocked)
    check = Check()
    a, b = _pair(run)
    control = _control(run, 'male')
    settings = _api(run, 'GET', '/cards/notification-settings', a['token'])
    if settings[0] != 200 or settings[1].get('quiet_hours') is not True:
        raise Blocked(f'방해 금지(quiet_hours)가 켜져 있어야 예외를 볼 수 있다 — 지금 {settings[0]} {settings[1]}')
    with _permitted(phone.serial), _every_day(run, a):
        _app(check, phone(token_hash=run.link(a['email'])))
        before = _ready(run, phone, a)
        notify.background(phone.serial)
        said = night_refusal(now_seoul(), skip_monday=True)  # 준비하는 사이 창을 벗어났으면 낮 결과가 된다
        if said:
            raise Blocked(f'밤 22:00~23:59 창을 벗어남 — {said}')
        if _issue(check, run, a, control=control):
            _one_notice(check, phone.serial, before)
    check.that(len(_daily_rows(run, a)) == 1, f'A 카드가 {len(_daily_rows(run, a))}장(기대 1)')
    return check.result('응답의 issued 개수는 스케줄러 호출이라 못 읽음 — A 의 daily_cards 행으로 확인')


def p_card_18(run, phone):
    """"오늘의 카드 도착" 을 끄면 카드는 생기지만 60초 내내 알림 0. 끄기는 API(16d 화면 토글은 E-SET-09 가 본다)."""
    require_daily_cards_open()
    notify.ensure_delivery(phone.serial)  # 푸시 연결이 죽은 폰은 FCM 200 인데도 안 떠서 "온다" 는 헛fail, "안 온다" 는 헛통과 — 계정을 만들기 전에 되살린다(또는 blocked)
    check = Check()
    a, b = _pair(run)
    control = _control(run, 'male')
    check.reply('알림 끄기', _api(run, 'PATCH', '/cards/notification-settings', a['token'], {'card_arrived': False}), 200)
    saved = _api(run, 'GET', '/cards/notification-settings', a['token'])
    check.that(saved[0] == 200 and saved[1].get('card_arrived') is False, f'끈 값이 서버에 안 남음: {saved[0]} {saved[1]}')
    if check.problems:
        return check.result()
    with _permitted(phone.serial), _every_day(run, a):
        _app(check, phone(token_hash=run.link(a['email'])))
        before = _ready(run, phone, a)
        notify.background(phone.serial)
        if _issue(check, run, a, control=control):
            seen = notify.expect_none(phone.serial, before, seconds=QUIET_WAIT)
            check.that(not seen, f'알림을 껐는데 {QUIET_WAIT}초 안에 새 알림 {len(seen)}건: {[n.title for n in seen]}')
    check.that(len(_daily_rows(run, a)) == 1, f'A 카드가 {len(_daily_rows(run, a))}장(기대 1)')
    return check.result()


def p_card_19(run, phone):
    """권한을 뺏고 배치 → 알림 0 → 다시 주고 카드를 만료시켜 배치 → 알림 1. 첫 카드의 상대는 14일 쉬므로 후보 C 를 하나 더 둔다."""
    require_daily_cards_open()
    notify.ensure_delivery(phone.serial)  # 푸시 연결이 죽은 폰은 FCM 200 인데도 안 떠서 "온다" 는 헛fail, "안 온다" 는 헛통과 — 계정을 만들기 전에 되살린다(또는 blocked)
    check = Check()
    a, b = _pair(run)
    c = _person(run, 'female')
    control = _control(run, 'male')
    serial = phone.serial
    with _every_day(run, a):
        notify.grant_notifications(serial)
        try:
            _app(check, phone(token_hash=run.link(a['email'])))
            _token_up(run, a)
            notify.revoke_notifications(serial)  # 권한을 빼면 안드로이드 13+ 는 앱 프로세스를 죽인다 — 그래서 앱 가설은 이미 끝낸 뒤다
            require_revoked(serial)
            before = notify.read_notifications(serial)
            notify.background(serial)
            if _issue(check, run, a, control=control):
                seen = notify.expect_none(serial, before, seconds=NOTICE_WAIT)
                check.that(not seen, f'권한을 뺏었는데 새 알림 {len(seen)}건: {[n.title for n in seen]}')
                notify.grant_notifications(serial)
                have, control_have = len(_daily_rows(run, a)), len(_daily_rows(run, control))
                _expire(run, a)
                _expire(run, control)  # 대조군도 만료시켜야 2회차 배치에서 새 카드를 받아 앵커가 된다
                before = notify.read_notifications(serial)
                if _issue(check, run, a, have, control, control_have):
                    _one_notice(check, serial, before)
        finally:
            notify.revoke_notifications(serial)
    return check.result('권한을 줬다 뺐다 하는 사이 알림 목록(dumpsys notification)만 본다')


def p_card_20(run, phone):
    """정지된 B(에뮬): 배치 → 카드 0 · 알림 0 / 정지를 풀고 배치 → 카드 1 · 알림 1. 같은 배치를 받은 대조군 C 가 카드를 받아야 "배치가 돌았다" 를 말할 수 있다."""
    require_daily_cards_open()
    emu.require_emulator(phone.serial)
    notify.ensure_delivery(phone.serial)  # 푸시 연결이 죽은 폰은 FCM 200 인데도 안 떠서 "온다" 는 헛fail, "안 온다" 는 헛통과 — 계정을 만들기 전에 되살린다(또는 blocked)
    check = Check()
    a, b = _pair(run)
    control = _person(run, 'female')
    with _permitted(phone.serial), _every_day(run, b):
        _app(check, phone(token_hash=run.link(b['email'])))  # 정지 전에 로그인해 기기 토큰을 올려 둔다(정지 계정은 등록이 막힐 수 있다)
        before = _ready(run, phone, b)
        notify.background(phone.serial)
        _set_status(run, b, 'suspended')
        try:
            area2._batch('daily-cards')
            if not _wait_for(lambda: _daily_rows(run, control), CARD_WAIT):
                raise Blocked(f'대조군 C 가 {CARD_WAIT}초 안에 카드를 못 받음 — 배치가 안 돈 것 같아 정지 계정이 카드를 안 받았다고 말할 수 없다')
            check.that(not _daily_rows(run, b), '정지된 B 가 카드를 받음')
            seen = notify.expect_none(phone.serial, before, seconds=ABSENCE_WAIT)
            check.that(not seen, f'정지된 B 에게 새 알림 {len(seen)}건: {[n.title for n in seen]}')
        finally:
            _set_status(run, b, 'active')
        if _issue(check, run, b, anchored=True):  # 1회차에 대조군 C 가 같은 배치로 카드를 받았다 — 배치는 돈다
            _one_notice(check, phone.serial, before)
    check.that(len(_daily_rows(run, b)) == 1, f'정지를 푼 뒤 B 카드가 {len(_daily_rows(run, b))}장(기대 1)')
    return check.result()


def p_card_03(run, phone):
    """앱이 화면 앞에 있는 채로 배치 → 30초 안에 카드가 목록에 저절로 나타나고(앱이 판정) 알림창에는 새 알림 0."""
    require_daily_cards_open()
    notify.ensure_delivery(phone.serial)  # 푸시 연결이 죽은 폰은 FCM 200 인데도 안 떠서 "온다" 는 헛fail, "안 온다" 는 헛통과 — 계정을 만들기 전에 되살린다(또는 blocked)
    check = Check()
    a, b = _pair(run)
    control = _control(run, 'male')

    def live(said):
        top = phone.top()
        if tools.PACKAGE not in top:
            raise Blocked(f'앱이 화면 앞에 없음({top[:80]}) — 앞에 둔 채 보는 가설이다')
        before = _ready(run, phone, a)
        if _issue(check, run, a, control=control):
            seen = notify.expect_none(phone.serial, before, seconds=NOTICE_WAIT)  # 카드가 생긴 뒤 30초 내내 — 앱이 이 사이에 목록을 새로 읽는다
            check.that(not seen, f'앱이 앞에 있는데 새 알림 {len(seen)}건(배너): {[n.title for n in seen]}')

    with _permitted(phone.serial), _every_day(run, a):
        _app(check, _slow(phone, 600)(midway=live, token_hash=run.link(a['email'])))
    check.that(len(_daily_rows(run, a)) == 1, f'A 카드가 {len(_daily_rows(run, a))}장(기대 1)')
    return check.result()


def p_card_13(run, phone):
    """A 의 후보를 전부 "쉬는 중" 으로 만든 뒤 배치 → 카드가 안 나가고 오늘 탭은 11b "지금은 소개할 사람이 없어요".
    후보 일시중지는 이번 실행 계정이 아니면 못 쓰므로, A 가 받았다가 방금 만료된 카드(14일 쉼, match_candidates ③)를 후보마다 넣는다."""
    require_daily_cards_open()
    check = Check()
    a, b = _pair(run)
    control = _person(run, 'male')

    def empty(said):
        pool = _candidates(run, a)
        if pool:
            now = area2._now()
            _insert(run, 'daily_cards', [{'id': _new_id(), 'owner_id': a['id'], 'target_id': t, 'source': 'daily',
                                         'issued_at': (now - timedelta(days=2)).isoformat(),
                                         'expires_at': (now - timedelta(hours=1)).isoformat()} for t in pool], a['id'])
        if _candidates(run, a):
            raise Blocked('준비: 후보를 다 쉬게 했는데도 A 의 후보가 남음 — 후보 0 상태를 못 만들었다')
        area2._batch('daily-cards')
        if not _wait_for(lambda: _daily_rows(run, control), CARD_WAIT):
            raise Blocked(f'대조군이 {CARD_WAIT}초 안에 카드를 못 받음 — 배치가 안 돈 것 같아 "카드가 안 나갔다" 를 말할 수 없다')
        today = _api(run, 'GET', '/cards/today', a['token'])
        ok = today[0] == 200 and not today[1].get('cards') and today[1].get('candidate_pool_empty') is True
        check.that(ok, f'A 의 /cards/today 가 빈 카드 + 후보 없음이 아님: {today[0]} {today[1]}')

    with _every_day(run, a):
        _app(check, _slow(phone, APP_WAIT)(midway=empty, token_hash=run.link(a['email'])))
    return check.result('응답의 no_candidate 수치는 스케줄러 호출이라 못 읽음 — 대조군 카드 · /cards/today · 앱 화면으로 확인')


def p_home_29(run, phone):
    """닫힌 학교에서 켜 둔 B → 학교를 연 뒤 배치 → B 카드 1장 + 알림이 정확히 1건(제목 "오늘의 카드가 도착했어요") — 따로 "오픈" 알림 0."""
    require_daily_cards_open()
    notify.ensure_delivery(phone.serial)  # 푸시 연결이 죽은 폰은 FCM 200 인데도 안 떠서 "온다" 는 헛fail, "안 온다" 는 헛통과 — 계정을 만들기 전에 되살린다(또는 blocked)
    check = Check()
    a, b = _pair(run)
    control = _control(run, 'female')
    now = now_seoul()
    with _permitted(phone.serial), _every_day(run, b), opens_at_set(run, future_monday(now)) as school:
        _app(check, phone(token_hash=run.link(b['email'])))
        _token_up(run, b)
        set_opens_at(run, school, past_monday(now))  # 여는 날이 됐다 — 이 뒤 첫 배치가 첫 카드를 준다
        before = notify.read_notifications(phone.serial)
        notify.background(phone.serial)
        if _issue(check, run, b, control=control):
            _one_notice(check, phone.serial, before)
    check.that(len(_daily_rows(run, b)) == 1, f'B 카드가 {len(_daily_rows(run, b))}장(기대 1)')
    return check.result()


# ── 시계 ────────────────────────────────────────────────────────────────────────────────────────────

def _judged_at(app, key, skew):
    """앱이 말한 기기 시각(ms) → PC 시각(서울). 없으면 None."""
    value = app.get(key)
    return None if value is None else datetime.fromtimestamp(value / 1000 - skew, SEOUL)


def p_home_23(run, phone):
    """닫힌 학교(미래 월요일) → 앱이 대기 화면 → 값을 지난 월요일 07:00 으로 옮기고 앱을 강제 종료 → 실행 → 대기 화면 0 · 히어로 1."""
    check = Check()
    account, token = _signed_in(run, 'home')
    now = now_seoul()
    with opens_at_set(run, future_monday(now)) as school:
        _app(check, phone(token_hash=token, phase='wait'), '대기 화면')
        set_opens_at(run, school, past_monday(now))
        _app(check, phone(fresh=False, phase='open'), '다시 켠 뒤')  # Run.phone 이 앞 프로세스를 kill -9 하고 새로 켠다
    return check.result()


def p_home_24(run, phone):
    """월요일 06:40~06:58 에 시작: 여는 시각 = 오늘 07:00 → 앱을 켜 둔 채 07:00 을 지나면 다시 켜지 않아도 09b, 서버 요청 간격 1분 미만 되풀이 0."""
    said = monday_morning_refusal(now_seoul())
    if said:
        raise Blocked(said)
    check = Check()
    account, token = _signed_in(run, 'home')
    opens = now_seoul().replace(hour=7, minute=0, second=0, microsecond=0)
    if (opens - now_seoul()).total_seconds() < LEAD_MIN:
        raise Blocked('준비가 늦어 07:00 전에 앱이 대기 화면에 못 닿음 — 더 일찍(06:50 쯤) 시작')
    skew = clock_skew(phone.serial)
    end = opens + timedelta(minutes=4)  # 07:04 — 07:02 허용 + 여유
    with opens_at_set(run, opens):
        said = _slow(phone, app_timeout(now_seoul(), end))(token_hash=token, deadline_ms=device_ms(end, skew))
        app = _app(check, said)
    at = _judged_at(app, 'opened_ms', skew)
    check.that(at is not None, '앱이 09b 로 바뀐 시각을 안 말함')
    if at is not None:
        check.that(opens <= at <= opens + timedelta(seconds=OPEN_LATE), f'09b 가 {at:%H:%M:%S} 에 보임(기대 07:00:00~07:02:00)')
    loads = app.get('loads_ms') or []
    gaps = [(later - sooner) / 1000 for sooner, later in zip(loads, loads[1:])]
    check.that(all(gap >= INTERVAL_MIN for gap in gaps), f'서버 요청 간격이 1분 미만인 되풀이가 있음: {gaps}초')
    return check.result(f'기기 시계 오차 {skew:+.0f}초 반영 · 요청 {len(loads)}번(앱이 요약을 다시 읽은 횟수 — 서버 로그가 아니다)')


def p_home_25(run, phone):
    """23:40~23:58 에 시작: 여는 날이 며칠 뒤인 학교 → 앱을 켜 둔 채 자정을 넘기면 다시 켜지 않아도 D-n → D-(n-1)."""
    said = midnight_refusal(now_seoul())
    if said:
        raise Blocked(said)
    check = Check()
    account, token = _signed_in(run, 'home')
    now = now_seoul()
    midnight = (now + timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
    if (midnight - now).total_seconds() < LEAD_MIN:
        raise Blocked('준비가 늦어 자정 전에 앱이 D-숫자를 못 그림 — 더 일찍(23:50 쯤) 시작')
    opens = future_monday(now, 2)  # 자정 뒤에도 D-day 가 아니라 D-숫자로 남게 이틀 이상
    days = (opens.date() - now.date()).days
    skew = clock_skew(phone.serial)
    end = midnight + timedelta(seconds=150)  # 00:02:30 — 00:01 허용 + 여유
    with opens_at_set(run, opens):
        said = _slow(phone, app_timeout(now_seoul(), end))(token_hash=token, days=days, deadline_ms=device_ms(end, skew))
        app = _app(check, said)
    at = _judged_at(app, 'flipped_ms', skew)
    check.that(at is not None, '앱이 D-숫자가 바뀐 시각을 안 말함')
    if at is not None:
        check.that(midnight <= at <= midnight + timedelta(seconds=FLIP_LATE), f'D-{days} → D-{days - 1} 가 {at:%H:%M:%S} 에 바뀜(기대 00:00:00~00:01:00)')
    return check.result(f'D-{days} → D-{days - 1} · 기기 시계 오차 {skew:+.0f}초 반영')


def p_home_26(run, phone):
    """여는 날 당일 07시 전 — 앱 시계 자리(homeNowProvider)를 그날 06:30 으로 바꿔 끼워 "D-day" · "오늘 오전 7시". 요일 · 시각 제약 없음.
    서버에는 아직 안 열린 값(미래 월요일)을 넣어 cohort 가 오게 하고, 앱 쪽이 시계만 여는 날 06:30 으로 보게 한다."""
    check = Check()
    account, token = _signed_in(run, 'home')
    opens = future_monday(now_seoul())
    with opens_at_set(run, opens):
        _app(check, phone(token_hash=token, opens_at=opens.isoformat()))
    return check.result('앱 시계 자리를 바꿔 끼움(lib/ 변경 0) — 실기기에서 아직 안 돌려 봄')


# ── 방해 금지 시간 2단계(E-CARD-44) ─────────────────────────────────────────────────────────────────

STATE_FILE = 'card44_state.json'  # 1단계가 남기고 아침 단계가 읽는다 — 하루를 건너므로 파일에
NIGHT_NOTE = ('1단계 끝 — 내일 08:10 뒤 같은 번호를 같은 --bundle 로 다시(상태 파일이 묶음 폴더 안). '
              '알림 권한은 아침까지 켜 둠(수동으로 빼지 말 것). '
              '아침 단계는 같은 묶음 다른 가설(권한을 빼는 01 · 17 · 18 · 19 등)보다 먼저 돌릴 것 — 권한을 빼면 이미 뜬 알림이 지워지는지 기기 미확인')


def _read_state(run):
    path = run.out / STATE_FILE
    return json.loads(path.read_text(encoding='utf-8')) if path.exists() else None


def _write_state(run, state):
    (run.out / STATE_FILE).write_text(json.dumps(state, ensure_ascii=False, indent=1), encoding='utf-8')


def p_card_44(run, phone):
    """밤(22:00~23:59)에 1단계, 다음 날 08:10~21:49 에 같은 번호로 2단계. 지금이 어느 쪽인지는 시각과 남긴 파일로 정한다.
    운영 순서: 1단계는 그날 밤 다른 가설들이 끝난 뒤에, 아침 단계는 같은 묶음 다른 가설(권한을 `_permitted` 로 빼는 01 · 17 · 18 · 19 등)보다 먼저 —
    권한을 빼면 이미 뜬 알림이 알림창에서 지워지는지는 기기 미확인이다."""
    state = _read_state(run)
    step, said = card44_step(now_seoul(), state)
    if said:
        raise Blocked(said)
    return _card44_morning(run, phone, state) if step == 'morning' else _card44_night(run, phone)


def _card44_night(run, phone):
    """B(폰)가 받는 사람. 방해 금지 켠 채 A1 이 수락 → 밤 알림 0 · 보관함 1행. 끄고 A2 가 수락 → 바로 알림. 보관 한 건을 파일에 남기고 blocked."""
    notify.ensure_delivery(phone.serial)  # 푸시 연결이 죽은 폰은 FCM 200 인데도 안 떠서 "온다" 는 헛fail, "안 온다" 는 헛통과 — 계정을 만들기 전에 되살린다(또는 blocked)
    check = Check()
    start = now_seoul()
    a1, a2, b = _person(run, 'male'), _person(run, 'male'), _person(run, 'female')
    c1, c2 = _card(run, a1, b), _card(run, a2, b)
    # 성공하면 알림 권한을 **빼지 않는다** — 권한이 빠진 폰은 08시 예약 chat-gate 가 FCM 을 보내도 알림창에 안 떠서 아침 단계가 거짓 fail 이 난다.
    notify.grant_notifications(phone.serial)
    kept = False
    try:
        _app(check, phone(token_hash=run.link(b['email'])))
        before = _ready(run, phone, b)
        notify.background(phone.serial)
        check.reply('A1 수락', _api(run, 'POST', f'/cards/{c1}/decision', a1['token'], {'decision': 'accept'}, **_ONCE), 200)
        seen = notify.expect_none(phone.serial, before, seconds=QUIET_WAIT)
        check.that(not seen, f'방해 금지 시간인데 밤 알림 {len(seen)}건: {[n.title for n in seen]}')
        held = _rows(run, f"pending_pushes?profile_id=eq.{b['id']}&select=id,kind,title,body")
        check.that(len(held) == 1 and held[0]['kind'] == 'acceptance_received',
                   f'pending_pushes 에 B 의 acceptance_received 행이 {len(held)}개(기대 1): {[h["kind"] for h in held]}')
        check.reply('방해 금지 끄기', _api(run, 'PATCH', '/cards/notification-settings', b['token'], {'quiet_hours': False}), 200)
        before = notify.read_notifications(phone.serial)
        check.reply('A2 수락', _api(run, 'POST', f'/cards/{c2}/decision', a2['token'], {'decision': 'accept'}, **_ONCE), 200)
        nickname = _one(run, f"profiles?id=eq.{a2['id']}&select=nickname").get('nickname')
        want = (NIGHT_TITLE, f'{nickname} 님이 대화를 하고 싶어 해요')
        new = notify.wait_new(phone.serial, before, seconds=NOTICE_WAIT)
        check.that(any((n.title, n.text) == want for n in new),
                   f'방해 금지를 끈 뒤 {NOTICE_WAIT}초 안에 알림 "{want[0]} / {want[1]}" 없음(새 알림 {len(new)}건)')
        check.that(len(_rows(run, f"pending_pushes?profile_id=eq.{b['id']}&select=id")) == 1, '방해 금지를 끈 뒤의 수락이 보관함에 들어감')
        if check.problems:
            return check.result()
        _write_state(run, {'night_date': start.date().isoformat(), 'receiver_id': b['id'], 'pending_id': held[0]['id'],
                           'title': held[0]['title'], 'text': held[0]['body']})
        kept = True
        return 'blocked', NIGHT_NOTE
    finally:
        if not kept:  # 실패 · 예외로 끝나면 권한을 되돌린다(성공하면 아침까지 켜 둔다)
            notify.revoke_notifications(phone.serial)


def _card44_morning(run, phone, state):
    """아침: 보관함 행이 사라지고 원문 알림이 알림창에 있다. 08시 예약 chat-gate 가 이미 보냈으면 손으로 안 부르고, 아직이면 관문을 지나 부른다."""
    notify.ensure_delivery(phone.serial)  # 푸시 연결이 죽은 폰은 FCM 200 인데도 안 떠서 "온다" 는 헛fail, "안 온다" 는 헛통과 — 계정을 만들기 전에 되살린다(또는 blocked)
    check = Check()
    _guard(run, state['receiver_id'])
    want = (state['title'], state['text'])
    held = f"pending_pushes?id=eq.{state['pending_id']}&select=id"
    notify.grant_notifications(phone.serial)  # 1단계가 켜 둔 채 왔어야 하지만 사람이 뺐을 수 있다 — 아침 알림은 권한이 있어야 알림창에 뜬다
    try:
        if _rows(run, held):
            before = notify.read_notifications(phone.serial)
            area2._batch('chat-gate')  # 정각 ±5분 · 같은 시 두 번은 관문이 막는다
            check.that(_wait_for(lambda: not _rows(run, held), CARD_WAIT), f'chat-gate 뒤 {CARD_WAIT}초 안에 보관함 행이 안 사라짐')
            shown, how = notify.wait_new(phone.serial, before, seconds=NOTICE_WAIT), '손으로 chat-gate(관문 통과)'
        else:
            shown, how = notify.read_notifications(phone.serial), '08시 예약 chat-gate 가 이미 보내 행이 없음'
        got = [n for n in shown if (n.title, n.text) == want]
        check.that(len(got) == 1, f'알림창에 "{want[0]} / {want[1]}" 가 {len(got)}개(기대 1) — 우리 앱 알림 {len(shown)}건(손으로 지웠는지 확인)')
        check.that(not _rows(run, f"pending_pushes?profile_id=eq.{state['receiver_id']}&select=id"), 'B 의 보관함 행이 남음')
        if not check.problems:
            _write_state(run, {**state, 'done': True})
        return check.result(f'{how}. chat-gate 응답의 deferred_sent 는 스케줄러 호출이라 못 읽음 — 보관함 행 · 알림창으로 확인')
    finally:
        notify.revoke_notifications(phone.serial)


PHONE = {
    'E-CARD-01': p_card_01, 'E-CARD-03': p_card_03, 'E-CARD-13': p_card_13, 'E-CARD-17': p_card_17, 'E-CARD-18': p_card_18,
    'E-CARD-19': p_card_19, 'E-CARD-20': p_card_20, 'E-HOME-29': p_home_29,
    'E-HOME-23': p_home_23, 'E-HOME-24': p_home_24, 'E-HOME-25': p_home_25, 'E-HOME-26': p_home_26, 'E-CARD-44': p_card_44,
}
A_PHONE = ['E-CARD-01', 'E-CARD-03', 'E-CARD-13', 'E-CARD-17', 'E-CARD-18', 'E-CARD-19', 'E-CARD-44']
B_EMULATOR = ['E-CARD-20', 'E-HOME-23', 'E-HOME-24', 'E-HOME-25', 'E-HOME-26', 'E-HOME-29']

area1.PHONE.update(PHONE)
area1.BUNDLES['area2-time-device'] = list(PHONE)
area1.BUNDLES['area2-time-device-a'] = A_PHONE
area1.BUNDLES['area2-time-device-b'] = B_EMULATOR
