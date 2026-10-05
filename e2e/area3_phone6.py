"""영역 3 E-CHAT-53 한 개 — 리마인드 시각이 밤(22~08시)에 걸리면 아침 8시로 밀린다: 07시대 배치엔 안 가고 08시대 배치에 간다(묶음 area3-phone-6). 앱 쪽은
frontend/integration_test/area3_b6.dart(로그인해 홈까지만 — 새 앱 로직 없음). 기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 3 의 그 줄이다.

가설은 **실제 시각**이 규칙이라서 한 번의 실행(약 70분)이 chat-gate 를 두 번 부른다 — 07시대 한 번, 08시대 한 번. 관문(batch_gate)의 "같은 시 두 번째 금지"는
날짜 + 시로 세므로 07시와 08시는 서로 다른 시라 막히지 않는다.
  07:06~07:40 시작  방 created_at = 서울 어제 03:00(24시간 뒤 = 오늘 03:00 → 서버가 08:00 으로 민다) → 배치 ① → B 새 알림 0건
  (대기)            방을 "지금" 으로 되돌려 젊게 해 둔다 — 매시 정각 Cloud Scheduler 의 진짜 chat-gate(`0 * * * *`, DEPLOY.md §4-1)가 08:00 에 먼저 돌아 B 에게 리마인드를
                    보내면, 08:06 의 수동 배치가 같은 시 두 번째라 08시대가 2건이 된다(chat/gate.py:65-66 알려진 한계)
  08:07 이후        방을 다시 어제 03:00 으로 → 배치 ② → B 의 리마인드 정확히 1건

시나리오와 다르게 도는 것(보고의 "확인 필요"):
  방 시각      "created_at = 어제 03:00 한 방으로 계속" → 07시대 판정 뒤 08시대 직전까지 방을 젊게 해 둔다(위). 07시대 판정에는 영향 없다(서버는 배치 순간의 값만 읽는다).
  07시대 0건    약한 증거다 — 창이 아직 안 와서 안 가는 것에 더해, 설령 와도 notify() 의 조용한 시간 검사가 버린다(cards/push.py:95-98). 밤 이동(gate.reminder_at)의
               증거는 08시대 1건이다(밀지 않으면 창이 03:00~04:00 이라 08시대엔 0건).
  "0건 · 1건" 의 믿음  배치가 돌았다 = 같은 실행이 만든 확인용 방(sentinel, 48시간 5분 지난 방)이 닫힘. 알림 길이 산다 = 07시대는 상대가 젊은 방에서 보낸 글(new_message 는 조용한 시간
               예외라 07시대에도 간다)이 도착. 08시대에 안 오면 같은 대조 알림이 오는지로 fail(길은 사는데 리마인드만 없음)과 blocked(1시간 놀던 FCM 이 죽었을 수 있음)를 가른다.
  A 쪽 알림    폰이 한 대라 B 만 본다(A 는 기기 토큰이 없다).
  낮에만 규칙   notify.require_daytime(08~22)을 쓰지 않는다 — 일부러 07시대에 돈다. 밤 보류 알림이 아침 배치에 섞이는 위험은 이 흐름이 보류 종류(수락 · 매칭 · 리뷰 · 학생증)를
               만드는 API 를 부르지 않아 없다(방은 DB 로, 보내기는 new_message 뿐). 판정은 (제목, 본문) 일치만 센다.
  실사용자      시작 때 실사용자 0 을 확인하므로(preflight) 08시대 수동 배치가 실사용자에게 중복 리마인드를 보낼 일은 없다 — 실사용자가 생긴 뒤에는 다시 평가한다.
  운영 규칙     07:06~08:15 는 이 가설 전용이다 — 08시대에 다른 chat-gate 가설을 돌리면 08시 슬롯을 먼저 먹는다.
"""

import contextlib
import secrets
import time
from datetime import timedelta, timezone

from e2e import area1, area3, batch_gate, notify, notify_factory, tools
from e2e.area1 import Check, _patch
from e2e.area2_phone3 import _wait_for, notice_memo
from e2e.area3 import _match
from e2e.area3_phone import _me, _permitted, _person
from e2e.area3_phone5 import (BATCH_WAIT, BODY, CLOSE_AGE, NOTICE_WAIT, SETTLE, TITLE, WATCH_MORE, _ages, _batch, _closed, _own, _park, _sentinel,
                              _single_shot)
from e2e.tools import Blocked

PREP_MINUTES = 14  # 준비(푸시 연결 점검 · 계정 7개 · 로그인) + 07시대 배치 기다림에 드는 시간의 넉넉한 값 — 07:40 시작이 07:54 에 끝난다
CONTROL_WAIT = 30  # 대조 알림을 기다리는 초(영역 4 PUSH A1 과 같다)
EIGHT = (8, 7)  # 08시대 배치를 부르는 서울 시·분 — 관문이 08:00~08:05 를 막고, PC · 서버 시계 오차 여유로 08:07
WAKE_STEP = 30  # 08시대를 기다리며 서울 시계를 다시 읽는 간격(초)
CASE_LIMIT = 5400  # 90분 — 07:06 시작 → 08:07 대기 61분 + 07시대 판정 ~8분 + 08시대 판정(확인용 방 ≤120 + 20 + 알림 60 + 10 + 대조 30 + 준비) ~5분 + 여유


def _nap(seconds):
    time.sleep(seconds)  # 시험이 가짜 시계를 흘리는 것으로 갈아 끼우는 자리


def _yesterday_three(now):
    """서울 시각 [now] 의 어제 03:00(서울). 24시간 뒤 = 오늘 03:00 이 조용한 시간(<8시)에 걸려 서버가 08:00 으로 민다."""
    return (now - timedelta(days=1)).replace(hour=3, minute=0, second=0, microsecond=0)


def _put_time(run, match_id, at):
    _patch(run, f'matches?id=eq.{match_id}', {'created_at': at.astimezone(timezone.utc).isoformat()})


def _make_young(run, match_id):
    """방을 지금 만든 것으로 — 08:00 예약 실행의 리마인드 창(내일 08:00)에 걸리지 않는다."""
    _put_time(run, match_id, batch_gate.now_seoul())


def _start():
    """준비 **전에** 부른다. 서울 07시대여야 하고, 관문이 지금 · 준비가 끝날 즈음(07:54 까지)에 열려 있어야 한다(기록 없이)."""
    now = batch_gate.now_seoul()
    if now.hour != 7:
        raise Blocked(f'서울 시각 {now:%H:%M} — 이 가설은 07:06~07:40 에 시작(07시대 배치 → 08시대 배치 한 번씩, 둘 다 한 실행에서)')
    batch_gate.peek('chat-gate', ahead=PREP_MINUTES)


def _batch_at(run, accounts, match_id, sentinel):
    """관문 → (통과하면) 방을 서울 어제 03:00 으로 · 확인용 방을 48시간 5분 지난 것으로 → chat-gate 한 번 → 확인용 방이 닫히길 기다림 → 나머지 방을 훑을 시간.
    배치를 부른 서울 시각을 돌려준다. area3_phone5._gated_batch 는 방 시각을 "지금 − 나이" 로만 옮겨 03:00 절대 시각을 못 넣어 8줄을 따로 둔다."""
    a, b, sentinel_id = sentinel
    _own(run, *accounts, a, b)
    called = []

    def before():
        called.append(batch_gate.now_seoul())
        _put_time(run, match_id, _yesterday_three(called[0]))
        _ages(run, [(sentinel_id, CLOSE_AGE)])

    _batch('chat-gate', before=before)
    if not _wait_for(lambda: _closed(run, sentinel_id), BATCH_WAIT):
        raise Blocked(f'배치를 부른 뒤 {BATCH_WAIT}초 안에 확인용 방(이번 실행이 만든 48시간 지난 방)이 안 닫힘 — 배치가 안 돌았거나 늦음(gcloud 로그에서 200 확인)')
    time.sleep(SETTLE)
    return called[0]


def _control(run, phone, ctl, room):
    """대조 알림 — 상대(ctl)가 젊은 방에서 한 줄 보낸다. new_message 는 조용한 시간 예외라 07시대에도 간다. 도착하면 True."""
    before = notify.read_notifications(phone.serial)
    body = f'E2E-ctl-{secrets.token_hex(3)}'
    notify_factory.send(run, ctl, room, body)
    want = (ctl['nickname'], body)
    new = notify.wait_new(phone.serial, before, seconds=CONTROL_WAIT, match=lambda n: (n.title, n.text) == want)
    return any((n.title, n.text) == want for n in new)


def _wait_until_eight():
    target = batch_gate.now_seoul().replace(hour=EIGHT[0], minute=EIGHT[1], second=0, microsecond=0)
    while batch_gate.now_seoul() < target:
        _nap(WAKE_STEP)


def p_chat_53(run, phone):
    _start()
    check = Check()
    notify.ensure_delivery(phone.serial)  # 푸시 연결이 죽은 폰이면 "0건" 을 믿을 수 없다 — 계정을 만들기 전에 되살린다(또는 blocked)
    me, token = _me(run)
    partner, ctl = _person(run), _person(run)
    _own(run, me, partner, ctl)
    sentinel = _sentinel(run)
    match_id = _match(run, me, partner)  # created_at 은 아직 안 옮긴다 — 배치 직전에 마지막으로
    room = notify_factory.match(run, me, ctl)  # 대조 알림이 올 젊은 방
    before = _park(check, run, phone, me, token)
    if before is None:
        return check.result()

    # ── 07시대: 0건 ──────────────────────────────────────────────────────────────────────────────────
    young = False
    try:
        at7 = _batch_at(run, [me, partner, ctl], match_id, sentinel)
        _make_young(run, match_id)  # 배치는 순간의 값만 읽는다 — 08:00 예약 실행이 보기 전에 서둘러 젊게
        young = True
    finally:
        if not young:  # 확인용 방 미닫힘 · gcloud 실패 · 위 PATCH 실패로 끊겨도 방을 어제 03:00 으로 남기지 않는다(남으면 08:00 예약 실행이 보낸다). 되돌리기 실패는 원래 오류를 가리지 않게 삼킨다
            with contextlib.suppress(Exception):
                _make_young(run, match_id)
    if batch_gate.now_seoul().hour >= 8:
        raise Blocked(f'07시대 배치({at7:%H:%M})를 마친 시각이 08:00 을 넘음 — 08:00 예약 실행이 어제 03:00 방을 이미 봤을 수 있어 08시대 "정확히 1건" 을 판정할 수 없음')
    seven = notify.expect_none(phone.serial, before, seconds=NOTICE_WAIT)
    check.that(not seven, f'07시대({at7:%H:%M} 배치)에 B 알림이 {len(seven)}건 옴(기대 0): {notice_memo(seven)}')
    seven_said = f'07시대({at7:%H:%M} 배치) ' + ('0건' if not seven else f'{len(seven)}건(fail)')
    if not _control(run, phone, ctl, room):
        raise Blocked(f'07시대 대조 알림이 {CONTROL_WAIT}초 안에 안 옴 — 알림 길(읽기 · 토큰 · FCM)이 살아 있는지 몰라 "0건" 을 믿을 수 없음 — {seven_said}'
                      + (f': {"; ".join(check.problems)}' if check.problems else ''))
    before8 = notify.read_notifications(phone.serial)  # 08:00 예약 실행이 보낸 것도 세도록, 예약 실행 **전**에 뜬다(대조 알림은 이미 도착해 빠진다)

    # ── 08시대: 정확히 1건 ───────────────────────────────────────────────────────────────────────────
    try:
        sentinel8 = _sentinel(run)  # 기다리는 동안 미리 — 08:06 준비 시간을 안 쓰려고
        _wait_until_eight()
        at8 = _batch_at(run, [me, partner, ctl], match_id, sentinel8)
        want = (TITLE, BODY)
        new = notify.wait_new(phone.serial, before8, seconds=NOTICE_WAIT, match=lambda n: (n.title, n.text) == want)
        if any((n.title, n.text) == want for n in new):  # 한 번만 왔는지 — 도착 뒤 더 지켜본다
            new = notify.wait_new(phone.serial, before8, count=999, seconds=WATCH_MORE)
        arrived = [n for n in new if (n.title, n.text) == want]
        if arrived:
            check.that(len(arrived) == 1, f'08시대({at8:%H:%M} 배치)에 리마인드 "{TITLE}" 가 {len(arrived)}건(기대 1) — 새 알림 {len(new)}건: {notice_memo(new)}')
        elif not _control(run, phone, ctl, room):
            raise Blocked(f'08시대({at8:%H:%M} 배치) 리마인드가 안 왔고 대조 알림도 {CONTROL_WAIT}초 안에 안 옴 — 1시간 놀던 푸시 길이 죽었을 수 있어 fail 로 못 박지 않음')
        else:
            check.problems.append(f'08시대({at8:%H:%M} 배치)에 리마인드가 0건(기대 1) — 대조 알림은 왔으니 알림 길은 살아 있음. 새 알림 {len(new)}건: {notice_memo(new)}')
    except Blocked as e:
        raise Blocked(f'{e} — {seven_said}') from e
    eight_said = f'08시대({at8:%H:%M} 배치) {len(arrived)}건'
    return check.result(f'{seven_said} · {eight_said}. A 쪽 알림은 못 봄(기기 없음). 07시대 0건은 창이 아직 안 온 것과 조용한 시간 검사가 겹친 약한 증거 — 밤 이동의 증거는 08시대 1건. '
                        f'방은 07시대 판정 뒤 08시대 직전까지 젊게 해 둠(08:00 예약 실행이 먼저 보내지 않게)')


PHONE6 = {'E-CHAT-53': _permitted(_single_shot(p_chat_53))}
tools.CASE_LIMITS.update({name: CASE_LIMIT for name in PHONE6})

area1.PHONE.update(PHONE6)
area3.BUNDLES['area3-phone-6'] = [*PHONE6]
