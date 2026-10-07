"""영역 2·4 미등록 가설 10개 — E-HEART-46 · 49 · 51, E-SET-04 · 12 · 26 · 43 · 52 · 53 · 67. 앱 쪽은 frontend/integration_test/area4_extra.dart 의 같은 번호.
기대값은 바탕화면 E2E_최종테스트_시나리오.md 의 그 줄(10-04 갱신)이되, 코드가 다르면 코드가 기준이다.

묶음(돌릴 때 기기가 다르다):
- area4-extra     폰 A: E-HEART-49 · 51, E-SET-04 · 12 · 26 (04 는 배치를 부른다 — 대장이 시각을 정해 돌린다)
- area4-extra-emu 에뮬 B(--device B): E-SET-43(배치) · 52 · 53 — 연락처 · 메일 앱을 건드려 실폰에서는 안 돈다
- area4-extra-two 폰 A + 에뮬 B: E-SET-67 (같은 계정으로 둘 다 로그인)
- area4-extra-ai  E-HEART-46 — 실제 AI 호출(비용) 이라 E2E_REAL_AI=1 일 때만

코드로 못 하는 6개는 등록하지 않는다 — E-HEART-06(디스코드 채널 코드는 코드로 못 읽음) · 47(운영에서 AI 실패를 일으킬 수 없음) · 50(노션 공개 페이지는 눈으로) ·
E-SET-55(운영 faq 표 수정 — 대장 10-04 skip) · 56 · 57(사람 필요).

시나리오와 다른 점: E-SET-12 · 26 은 시나리오가 "두 기기" 인데 폰 한 대로 한다 — "다른 기기" 가 한 일(스위치 끄기 · 차단)을 PC 가 서버에 직접 한다.
"다른 기기가 끈 것을 이 앱이 다시 읽는가" 는 보지만 다른 기기 앱의 화면 조작은 안 본다. E-HEART-46 의 서버 경고 로그는 DB 로 못 읽어 메모에 밝힌다.
"""

import contextlib
import re
import time

from e2e import area1, area2, area2_phone3, area2_time_batch, area3, area4, batch_gate, emu, notify, tools, twodev
from e2e.area1 import Check, _api, _app, _one, _rows
from e2e.area1_emu import _emulator
from e2e.area2 import _ONCE, _guard
from e2e.area2_two_accept import _after, _nickname, _verdict
from e2e.area3_phone5 import _single_shot
from e2e.area3_contacts import FRIEND, _blocks, _friends, _mutually_excluded, _session
from e2e.area4_contacts import people
from e2e.area5_photo import COST, _hearts_to, _two_ready
from e2e.area5_read import _ready_avatars
from e2e.tools import Blocked

SUPPORT_MAIL = 'appmailerl4538@gmail.com'  # frontend/lib/faq/view/faq_screen.dart
HOLD = 300  # E-SET-67: A 가 로그아웃한 뒤 B 가 그대로인지 보기 전에 기다리는 시간(초) — 시나리오 "5분 뒤"
SEEN = 10  # 앱이 누른 뒤 맨 위 화면이 바뀌기를 기다리는 시간(초) — 처음 여는 앱은 5초를 넘기기도 한다
# 계정 탈퇴(/account/withdraw)는 하트 출금이 아니다 — 'withdraw' 는 하트 이름이 붙은 경로만 센다.
FORBIDDEN_HEART = ('refund', 'cashout', 'transfer', 'gift', 'send_heart', 'send-heart', 'exchange',
                   'heart_withdraw', 'heart-withdraw', 'hearts/withdraw')
FORBIDDEN_STORE = ('heart_store', 'heart-store', 'unlock_card', 'unlock-card', 'buy_card', 'buy-card')


# ── E-HEART-46 아바타 만드는 중 잔액이 모자라지면 무료 ─────────────────────────────────────────────────

def heart_46(run):
    """완성 2장 · 하트 10(다시 만들기 값 10) → 만들기 시작(202) → 만드는 중 하트를 5 로 낮춤(−5, 값 10 에 모자람) → 3번째 완성을 기다림 →
    하트 5 그대로 · 음수 아님 · avatar_regen 원장 0(완성 뒤 차감이 모자라 무료로 처리됨). 실제 AI 라 E2E_REAL_AI=1 일 때만, 한 번만(비용 — area2_phone3._PAID)."""
    area2_phone3.real_ai_gate()
    case = 'E-HEART-46'
    if case in area2_phone3._PAID:
        result, note = area2_phone3._PAID[case]
        if result == 'fail':
            return result, f'{note} — 유료 호출 뒤라 다시 하지 않음'
        raise Blocked(f'이미 한 번 유료 호출 — 재시도 안 함(앞 결과 {result}: {note})')
    check = Check()
    account = area2._home(run)
    _two_ready(run, account)
    _hearts_to(run, account, 2 * COST - COST)  # 10 — 값(10) 만큼 정확히
    reply = _api(run, 'POST', '/me/avatar/regenerate', account['token'], **_ONCE)
    check.reply('만들기 요청', reply, 202)
    if reply[0] != 202:
        raise Blocked(f'만들기 요청이 {reply[0]} — 비용은 안 나갔고 더 못 간다')
    area2_phone3._PAID[case] = ('blocked', '만들기를 누른 뒤 결과가 나오기 전에 멈춤')  # 202 부터는 비용이 나간다
    try:
        _hearts_to(run, account, COST // 2)  # 만드는 중 5 로 — 서버가 완성 뒤 값(10)을 못 받게
        during = area2._ledger(run, account, 'avatar_regen')
        check.that(not during, f'만드는 중 avatar_regen 원장 {during}(기대 0행 — 차감은 완성 뒤)')
        if not area2_phone3._wait_for(lambda: len(_ready_avatars(run, account)) >= 3, area2_phone3.AI_WAIT):
            raise Blocked(f'{area2_phone3.AI_WAIT}초 안에 3번째 아바타가 안 완성됨 — AI 쪽 문제인지 구분 못 함')
        time.sleep(area2.SETTLE_SECONDS)  # 서버는 완성을 적은 뒤에 차감한다 — 늦게 오는 차감을 기다린다
        have = area2_phone3._balance(run, account)
        check.that(have == COST // 2, f'완성 뒤 하트 {have}(기대 {COST // 2} 그대로 — 모자라면 무료)')
        check.that(have >= 0, f'완성 뒤 하트가 음수 {have}')
        after = area2._ledger(run, account, 'avatar_regen')
        check.that(not after, f'완성 뒤 avatar_regen 원장 {after}(기대 0행 — 모자라 차감 안 함)')
        result = check.result('서버가 남기는 경고 로그(차감 실패)는 DB 로 못 읽음 — 하트 · 원장 · 완성 장수로만 봄')
    except Blocked as e:
        area2_phone3._PAID[case] = ('blocked', str(e))
        raise
    area2_phone3._PAID[case] = result
    return result


# ── E-HEART-49 · 51 하트 환급 · 선물 · 스토어 경로가 없다 ───────────────────────────────────────────────

def _paths(run, token):
    """서버가 광고하는 경로들(/openapi.json) — 못 읽으면 blocked(못 읽고 "없다" 로 통과하면 안 된다)."""
    status, body = _api(run, 'GET', '/openapi.json', token)[:2]
    if status != 200 or not isinstance(body, dict) or not isinstance(body.get('paths'), dict):
        raise Blocked(f'openapi 를 못 읽음({status}) — 경로 없음을 확인할 수 없다')
    return [path.lower() for path in body['paths']]


def _named(paths, words):
    return sorted(p for p in paths if any(w in p for w in words))


def heart_49(run, phone):
    """하트를 현금으로 바꾸거나(환급) 남에게 주는(선물 · 송금) 경로가 서버에 없고, 나 탭 · 설정에도 그런 글이 없다(화면은 앱이)."""
    check = Check()
    account = area2._home(run)
    found = _named(_paths(run, account['token']), FORBIDDEN_HEART)
    check.that(not found, f'서버에 하트 환급 · 선물 경로가 있음: {found}')
    _app(check, phone(token_hash=run.link(account['email'])))
    return check.result('서버 경로는 /openapi.json 이름으로 본다(' + ' · '.join(FORBIDDEN_HEART) + ')')


def heart_51(run, phone):
    """하트 쓰는 곳은 아바타 다시 만들기 하나 — 잠긴 카드(한 명 더) · 하트 스토어가 없다: /cards/today 의 locked_card_available 이 False 이고
    서버에 스토어 · 카드 구매 경로가 없으며, 오늘 · 나 · 설정에도 그런 글이 없다(화면은 앱이)."""
    check = Check()
    account = area2._home(run)
    today = _api(run, 'GET', '/cards/today', account['token'])
    check.reply('오늘 카드', today, 200)
    if today[0] == 200:
        got = (today[1] or {}).get('locked_card_available')
        check.that(got is False, f'locked_card_available {got!r}(기대 False)')
    found = _named(_paths(run, account['token']), FORBIDDEN_STORE)
    check.that(not found, f'서버에 하트 스토어 · 카드 구매 경로가 있음: {found}')
    _app(check, phone(token_hash=run.link(account['email'])))
    return check.result()


# ── E-SET-04 매칭 활성화를 끄면 카드가 안 나간다 ───────────────────────────────────────────────────────

def p_set_04(run, phone):
    """A(남)가 16 에서 "매칭 활성화" 를 끄면 matching_paused 가 저장되고, 배치를 불러도 A 는 카드 0장이며 다른 사람의 후보에서도 빠진다.
    같은 배치에서 대조군 남자는 카드를 받아야 한다(그래야 배치가 돈 것). 배치를 부른다 — 시각은 대장이 정한다."""
    region, today, check = area2_time_batch._prepare(run), batch_gate.now_seoul(), Check()
    a, b, c = area2._person(run, 'male'), area2._person(run, 'female'), area2._person(run, 'female')
    control = area2_time_batch._control_man(run)
    area2_time_batch._must_see(run, a, b, 'A 에게 줄 후보 B 가 없다')
    area2_time_batch._must_see(run, b, a, 'B 의 후보에 A 가 없다')
    area2_time_batch._must_see(run, control, c, '대조군에게 줄 후보 C 가 없다')
    _app(check, phone(token_hash=run.link(a['email'])), '끄기')
    paused = _one(run, f"profiles?id=eq.{a['id']}&select=matching_paused").get('matching_paused')
    check.that(paused is True, f'matching_paused {paused!r}(기대 True — 앱이 저장해야 한다)')
    check.that(a['id'] not in area2._candidates(run, b), '끈 A 가 B 의 후보에 그대로 있음')
    area2_time_batch._issue(run, region, list(area2_phone3.EVERY_DAY), control=[control])
    area2_time_batch._still_today(today)
    cards = area2_time_batch._cards(run, a)
    check.that(not cards, f'끈 A 에게 카드가 {len(cards)}장 나감(기대 0)')
    return check.result(area2_time_batch._zero_note(control=True))


# ── E-SET-12 · 26 다른 기기가 한 일을 이 앱이 다시 읽는다(폰 한 대로) ───────────────────────────────────

def p_set_12(run, phone):
    """16d 에서 "새 메시지" 스위치가 켜진 것을 보고(1), "다른 기기" 가 끈 뒤(PC 가 서버에 씀) 그 화면은 아직 켜 둔 그대로(2 — 앱이 안 다시 읽었으니),
    앱을 다시 켜서 읽으면 꺼짐(3). 시나리오는 기기 둘(B에뮬 → A폰) — 여기서는 폰 한 대 + PC 가 B 역할."""
    check = Check()
    account = area2._home(run)
    mine = account['id']
    before = area4._settings(run, mine).get('new_message', area4.DEFAULTS['new_message'])
    if before is not True:
        raise Blocked(f'준비: new_message 가 {before!r} — 켜져 있어야 한다')

    def other_device(said):
        _guard(run, mine)
        # 새 계정은 notification_settings 행이 없다(16d 를 열어도 읽기만 한다) — DB PATCH 는 없는 행에 아무 일도 안 하므로 다른 기기가 쓰는 길(앱 경로, upsert)로 쓴다
        check.reply('다른 기기의 스위치 끄기', _api(run, 'PATCH', '/cards/notification-settings', account['token'], {'new_message': False}, **_ONCE), 200)
        if area4._settings(run, mine).get('new_message') is not False:
            raise Blocked('준비: 다른 기기 역할의 스위치 끄기가 서버에 안 들어감')

    _app(check, phone(token_hash=run.link(account['email']), phase='opened', midway=other_device), '끄기 전 · 다른 기기가 끈 직후')
    _app(check, phone(fresh=False, phase='relaunched'), '다시 켠 뒤')
    got = area4._settings(run, mine).get('new_message')
    check.that(got is False, f'서버의 new_message {got!r}(기대 False — 앱이 되쓰지 않아야 한다)')
    return check.result('기기 둘 대신 폰 한 대 · PC 가 다른 기기 역할(스위치 끄기)')


def _left_at(run, room, account):
    rows = _rows(run, f"match_participants?match_id=eq.{room}&profile_id=eq.{account['id']}&select=left_at")
    return rows[0]['left_at'] if rows else 'ROW-GONE'


def p_set_26(run, phone):
    """A 가 B 를 차단하면 대화방을 나가고, 16f 에서 차단을 풀면 blocks 행이 지워지지만 방은 돌아오지 않는다(left_at 그대로 · 대화 탭에 B 없음 — 화면은 앱이).
    시나리오는 기기 둘 — 여기서는 폰 한 대, 차단은 PC 가 A 의 API 로 한다."""
    check = Check()
    a, b = area2._person(run, 'male'), area2._person(run, 'female')
    room = area3._match(run, a, b)
    check.reply('A 의 차단', _api(run, 'POST', f"/blocks/{b['id']}", a['token']), 200)
    if _left_at(run, room, a) in (None, 'ROW-GONE'):
        raise Blocked('준비: 차단했는데 A 가 대화방을 안 나감')
    _app(check, phone(token_hash=run.link(a['email']), nickname=_nickname(run, b)))
    rows = _rows(run, f"blocks?blocker_id=eq.{a['id']}&blocked_id=eq.{b['id']}&select=blocker_id")
    check.that(not rows, f'차단 해제 뒤 blocks 행 {len(rows)}개(기대 0)')
    left = _left_at(run, room, a)
    check.that(left not in (None, 'ROW-GONE'), f'차단 해제 뒤 left_at {left!r}(기대 값이 그대로 — 방은 복구되지 않는다)')
    return check.result('기기 둘 대신 폰 한 대 · 차단은 PC 가 A 의 API 로')


# ── E-SET-43 연락처로 막은 사람과는 배치에서도 서로 안 나온다(에뮬) ───────────────────────────────────

def p_set_43(run, phone):
    """B(남, 앱 사용자)의 연락처에 F(여)의 번호가 있고 B 가 그 사람을 차단하면 contact_blocks 한 줄, 배치를 불러도 B→F · F→B 카드가 0장.
    같은 배치에서 대조군 남자는 카드를 받아야 한다. 에뮬 전용 + 배치 — 시각은 대장이 정한다."""
    _emulator(phone)
    region, today, check = area2_time_batch._prepare(run), batch_gate.now_seoul(), Check()
    b, f = _friends(run)
    control = area2_time_batch._control_man(run)
    area2_time_batch._must_see(run, control, f, '대조군에게 줄 후보 F 가 없다')
    crowd = people(2) + [(FRIEND, (f['phone'],))]
    _session(run, phone, b, crowd, True, check, pick_names=[FRIEND], rows=1)
    rows = _blocks(run, b)
    check.that(len(rows) == 1, f'contact_blocks {len(rows)}행(기대 1)')
    _mutually_excluded(check, run, b, f, '차단 뒤 ')
    area2_time_batch._issue(run, region, list(area2_phone3.EVERY_DAY), control=[control])
    area2_time_batch._still_today(today)
    for label, owner, target in (('B→F', b, f), ('F→B', f, b)):
        cards = [r for r in area2_time_batch._cards(run, owner) if r['target_id'] == target['id']]
        check.that(not cards, f'{label} 카드 {len(cards)}장(기대 0)')
    return check.result(area2_time_batch._zero_note(control=True))


# ── E-SET-52 · 53 FAQ 의 문의 메일(에뮬) ────────────────────────────────────────────────────────────────

MAIL_VIEW = ('shell', 'pm', 'query-activities', '--brief', '-a', 'android.intent.action.SENDTO', '-d', 'mailto:')


def mail_apps(serial):
    """mailto: 를 받을 수 있는 앱의 패키지들(emu.browsers 와 같은 읽기)."""
    out = tools.adb(serial, *MAIL_VIEW, check=False)
    return sorted({m.group(1) for line in out.splitlines() if 'priority=' not in line and (m := re.match(r'\s*([\w.]+)/\S+', line))})


@contextlib.contextmanager
def mail_disabled(serial):
    """mailto: 를 받는 앱을 모두 `pm disable-user` 로 끈다 — 끝나면(실패해도) 다시 켠다. 못 끄면 blocked(emu.browsers_disabled 와 같은 규칙)."""
    emu.require_emulator(serial)
    off = set()
    try:
        for _ in range(4):
            found = mail_apps(serial)
            if not found:
                break
            for package in found:
                out = tools.adb(serial, 'shell', 'pm', 'disable-user', '--user', '0', package, check=False)
                if 'disabled-user' not in out:
                    raise Blocked(f'메일 앱 {package} 를 못 끔: {out.strip()}')
                off.add(package)
        else:
            raise Blocked(f'메일 앱이 끈 뒤에도 남음: {", ".join(mail_apps(serial))}')
        yield
    finally:
        for package in sorted(off):
            tools.adb(serial, 'shell', 'pm', 'enable', package, check=False)


def mail_intent_to(serial, address):
    """`dumpsys activity activities` 에 이 주소로 간 메일 Intent 줄이 있는지 — 구글 계정이 없는 에뮬은 Gmail 이 작성 화면 대신 첫 실행 화면만 띄워
    화면 글자로는 받는 사람을 못 읽지만, Intent 줄(act=…SENDTO|VIEW dat=mailto:주소 …)은 가려지지 않고 남는다. act 와 dat 가 **같은 줄**에 있어야 한다.
    앱이 쓰는 url_launcher 의 openUrl 은 SENDTO 가 아니라 **VIEW** 로 보낸다(에뮬 dumpsys 실측) — 둘 다 인정한다. 주소는 뒤에 글자가 더 붙으면(…evil) 다른 주소다."""
    out = tools.adb(serial, 'shell', 'dumpsys', 'activity', 'activities', check=False)
    mail = re.compile(r'act=android\.intent\.action\.(SENDTO|VIEW)\b.*\bdat=mailto:' + re.escape(address) + r'(?=[\s?,]|$)')
    return any(mail.search(line) for line in out.splitlines())


def p_set_52(run, phone):
    """FAQ 의 문의 메일 줄을 누르면 메일 앱이 맨 위로 뜨고 받는 사람이 문의 주소다. 앱은 누르자마자 pass 를 말한다(밖으로 나가면 앱 프레임이 멎는다) —
    메일 앱이 떴는지는 여기서 본다. 에뮬은 실제 Gmail 이 없어 임시 보관 메일이 남지 않는다."""
    serial = _emulator(phone)
    check = Check()
    apps = mail_apps(serial)
    if not apps:
        raise Blocked('준비: 에뮬에 mailto: 를 받는 메일 앱이 없음')
    account = area2._home(run)
    for app in apps:  # 옛 작성 task 가 남아 있으면 이 누름이 아니라 옛 Intent 로 통과할 수 있다 — 누르기 전에 끝낸다
        tools.adb(serial, 'shell', 'am', 'force-stop', app, check=False)
    _app(check, phone(token_hash=run.link(account['email'])))
    top = ''
    for _ in range(SEEN):
        top = phone.top()
        if any(app in top for app in apps):
            break
        time.sleep(1)
    check.that(any(app in top for app in apps), f'맨 위 화면이 메일 앱이 아님({", ".join(apps)}): {top or "못 읽음"}')
    if any(app in top for app in apps):
        # 받는 사람 = dumpsys 의 메일 Intent 줄(구글 계정이 없는 에뮬은 화면 글자로 못 읽는다) 또는 화면 글자(계정 있는 기기)
        check.that(mail_intent_to(serial, SUPPORT_MAIL) or notify.screen_has(serial, SUPPORT_MAIL),
                   f'받는 사람 {SUPPORT_MAIL} 을 메일 Intent 줄(SENDTO · VIEW)에서도 메일 앱 화면에서도 못 찾음')
    return check.result('받는 사람은 dumpsys 의 메일 Intent 줄(SENDTO · VIEW)로 읽음(에뮬에 구글 계정이 없어 Gmail 은 첫 실행 화면만 띄운다)')


def p_set_53(run, phone):
    """메일 앱이 하나도 없는 기기에서 문의 메일 줄을 누르면 앱 안에 "알 수 없는 오류가 발생했습니다" 안내가 뜨고 약 3초 뒤 사라진다(화면은 앱이).
    메일 앱을 끄는 것은 에뮬에서만, 끝나면(실패해도) 되켠다."""
    serial = _emulator(phone)
    check = Check()
    account = area2._home(run)
    with mail_disabled(serial):
        _app(check, phone(token_hash=run.link(account['email'])))
    return check.result()


# ── E-SET-67 같은 계정을 두 기기에서 — 한쪽이 로그아웃해도 다른 쪽은 그대로 ──────────────────────────────

LIMITS = {'side_timeout': {'A': 600, 'B': 900}, 'deadline': 1500}  # 다음 말까지 기다리는 시간 · 전체 상한(twodev.two) — B 는 HOLD 도 기다린다
CASE_LIMIT = 1800


def two_set_67(run, two):
    """같은 계정으로 A폰 · B에뮬 둘 다 로그인(B 가 대화 탭에서 상대 방을 본다) → A 가 로그아웃하면 A 는 로그인 화면 → B 는 곧바로(b-in)도, 5분 뒤(b-now)에도
    쫓겨나지 않고 대화 탭이 그대로다(화면은 앱이). 로그아웃은 이 기기만 — 서버에서 세션을 끊지 않는다(PC 는 계정이 그대로인지 본다).
    1회용 로그인 토큰은 같은 계정이 새로 받으면 앞 것이 죽으므로 B 의 것은 A 가 로그인한 뒤에 받는다."""
    check = Check()
    me, partner = area2._person(run, 'male'), area2._person(run, 'female')
    area3._match(run, me, partner)
    nickname = _nickname(run, partner)

    def a_in(said, sync):
        sync.set('a-in')
        _after(sync, 'b-in', 'B')

    def a_out(said, sync):
        sync.set('a-out')

    def b_wait(said, sync):
        _after(sync, 'a-in', 'A')
        return {'token_hash': run.link(me['email'])}

    def b_in(said, sync):
        sync.set('b-in')
        _after(sync, 'a-out', 'A')
        check.reply('A 로그아웃 뒤 서버 쪽 계정', _api(run, 'GET', '/me/profile', me['token']), 200)

    def b_now(said, sync):
        time.sleep(HOLD)  # 시나리오 "5분 뒤" — A 가 먼저 끝나 Sync 가 abort 돼도 B 는 끝까지 기다린다(Sync.wait 는 abort 면 Aborted 를 던진다)

    result, memo = two({('A', 'a-in'): a_in, ('A', 'a-out'): a_out, ('B', 'wait'): b_wait, ('B', 'b-in'): b_in, ('B', 'b-now'): b_now},
                       a_job={'token_hash': run.link(me['email']), 'nickname': nickname}, b_job={'nickname': nickname, 'hold': HOLD},
                       **LIMITS)
    return _verdict(check, result, memo, f'B 는 로그아웃 {HOLD}초 뒤에도 본다')


# ── 등록 ─────────────────────────────────────────────────────────────────────────────────────────────

CASES = {'E-HEART-46': heart_46}  # 폰 없이 `(run)`
PHONE = {
    'E-HEART-49': heart_49, 'E-HEART-51': heart_51, 'E-SET-12': p_set_12, 'E-SET-26': p_set_26,
    'E-SET-52': p_set_52, 'E-SET-53': p_set_53,
    # 배치를 부르는 둘 — fail 로 다시 돌면 운영 배치를 또 부르고 둘째 시도는 시각 관문에 막혀 진짜 fail 을 덮는다.
    'E-SET-04': _single_shot(p_set_04, always=True), 'E-SET-43': _single_shot(p_set_43, always=True),
}
TWO = {'E-SET-67': lambda run, two: area2.attempt_with(run, lambda run: two_set_67(run, two))}

BUNDLE_PHONE = ['E-HEART-49', 'E-HEART-51', 'E-SET-04', 'E-SET-12', 'E-SET-26']
BUNDLE_EMU = ['E-SET-43', 'E-SET-52', 'E-SET-53']

area1.CASES.update(CASES)
area1.PHONE.update(PHONE)
twodev.TWO.update(TWO)
area1.BUNDLES['area4-extra'] = BUNDLE_PHONE
area1.BUNDLES['area4-extra-emu'] = BUNDLE_EMU
area1.BUNDLES['area4-extra-two'] = list(TWO)
area1.BUNDLES['area4-extra-ai'] = list(CASES)
tools.CASE_LIMITS['E-SET-67'] = CASE_LIMIT
# 배치를 부르는 둘 — 기본 420초는 계정 준비 + 앱 + 첫 배치 120초 + 카드 90초(43 은 연락처 세션까지)에 모자라고, 한도에 걸리면 배치는 이미 나간 뒤라 다시 못 돈다
tools.CASE_LIMITS.update({'E-SET-04': 900, 'E-SET-43': 900})
