"""영역 4 알림(PUSH) 두 기기(폰 A + 에뮬 B) 3개 — E-PUSH-64 · 65 · 71(묶음 area4-push-two). 같은 계정으로 두 기기가 로그인한 상태에서 보는 것이다.
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 4 의 그 줄이되, 코드가 다르면 코드가 기준이다. 앱 쪽은 frontend/integration_test/area4_push_two.dart 의 같은 번호(`번호/A` · `번호/B`).
돌릴 때: A폰 + B에뮬을 둘 다 연결하고 `python -m e2e run area4-push-two`. 서울 08~22시에만 돈다(64 · 65 는 알림이 가는 가설이라 밤에는 결과가 달라진다).

"알림 하나 보내기" 는 area4_push_a4 와 같이 "받은 수락" 알림이다. 1회용 토큰은 같은 계정이 새로 받으면 앞 것이 죽으므로 B 는 A 가 로그인한 뒤 새 토큰을 받아 로그인한다.
알림을 읽는 일은 PC 가 B 쪽 핸들러에서 두 기기를 차례로 읽는다 — 기기마다 최대 60초.
알려진 한계: 71 의 "알림 0" 은 안 본다 — 탈퇴한 계정에는 알림을 보낼 수도 없다. 71 의 B 는 스스로 알아채는 데 최대 1시간이라 앱이 세션 새로고침을 앞당겨 부른다.
"""

from e2e import area1, notify, tools, twodev
from e2e.area1 import Check
from e2e.area2_two_accept import _after
from e2e import notify_factory
from e2e.area1 import _one
from e2e.area4_push_a4 import GONE_WAIT, TOKEN_WAIT, _arrived, _need_token, _quiet, _tokens, _wait
from e2e.area2_two_accept import _verdict
from e2e.tools import Blocked

CASE_LIMIT = 1800  # 가설 하나 상한(초) — 계정 · 두 기기 로그인 + 알림 기다림 두 번
LIMITS = {'side_timeout': {'A': 900, 'B': 900}, 'deadline': 1500}  # 다음 말까지 기다리는 시간 · 전체 상한(twodev.two)


def _setup(run, two, *, push):
    """계정 하나 · 두 기기 시리얼. [push] 면 알림을 보내는 가설이라 낮에만 돌고 두 기기 모두 알림이 닿게 준비한다."""
    serials = getattr(two, 'serials', None) or {}
    if set(serials) != {'A', 'B'}:
        raise Blocked('두 기기 시리얼을 못 받음')
    if push:
        notify.require_daytime()
        for serial in serials.values():
            notify.ensure_delivery(serial)
    return run.account('home'), serials, run.account('home') if push else None  # 보내는 계정도 메인 스레드에서 — 핸들러는 Run 을 안 만진다


def _joined(run, account, check, seen):
    """A 가 로그인해 토큰을 올리고(a_in) B 가 그 뒤에 로그인해 같은 계정에 둘째 토큰이 생긴다(b_wait · b_in) — 세 핸들러."""
    def a_in(said, sync):
        _need_token(run, account, 'A 폰의 기기 토큰이 안 올라옴')
        seen['a'] = {row['token'] for row in _tokens(run, account['id'])}
        sync.set('a-in')

    def b_wait(said, sync):
        _after(sync, 'a-in', 'A')
        return {'token_hash': run.link(account['email'])}

    def b_in(said, sync):
        _wait(lambda: len(_tokens(run, account['id'])) >= 2, TOKEN_WAIT)
        rows = _tokens(run, account['id'])
        tokens = {row['token'] for row in rows}
        check.that(len(rows) == 2 and len(tokens) == 2, f'두 기기가 로그인한 뒤 push_tokens {rows} — 서로 다른 토큰 2행이어야 함')
        check.that(seen['a'] <= tokens, f'A 폰의 토큰 {seen["a"]} 이 B 가 로그인한 뒤 사라짐 — 같은 계정의 다른 기기 토큰은 남아야 함')
        seen['b'] = tokens - seen['a']
    return a_in, b_wait, b_in


def _send_from(run, sender, receiver):
    """"알림 하나 보내기" — 미리 만든 [sender] 가 [receiver] 에게 카드를 만들어 수락한다 → 보낸 사람 닉네임(알림 본문에 든다)."""
    nickname = _one(run, f"profiles?id=eq.{sender['id']}&select=nickname").get('nickname')
    if not nickname:
        raise Blocked('보낸 계정의 닉네임을 못 읽음')
    notify_factory.accept_card(run, sender, notify_factory.card(run, sender, receiver))
    return nickname


def _notified(run, sender, account, serials, check, who):
    """알림 하나를 보내고 [who] = {기기: 와야 하면 True} 대로 오는지 — 어긋나면 check 에 적는다."""
    for serial in serials.values():
        notify.background(serial)
    before = {name: notify.read_notifications(serial) for name, serial in serials.items()}
    nickname = _send_from(run, sender, account)
    for name, serial in serials.items():
        if who[name]:
            check.that(_arrived(serial, before[name], nickname), f'{name} 에 알림이 {notify.NOTICE_WAIT}초 안에 안 옴')
        else:
            got = _quiet(serial, before[name])
            check.that(not got, f'{name} 에 알림 {len(got)}개가 옴 — 오면 안 되는 기기')


# ── 64 두 기기 모두에 알림 ─────────────────────────────────────────────────────────────────────────

def push_64(run, two):
    """같은 계정으로 두 기기가 로그인하면 push_tokens 가 2행이고 알림 하나가 두 기기 모두에 온다. 근거: push.py:73,86-89(계정의 토큰 전부에 보낸다)."""
    check, seen = Check(), {}
    account, serials, sender = _setup(run, two, push=True)
    a_in, b_wait, b_in = _joined(run, account, check, seen)

    def b_both(said, sync):
        b_in(said, sync)
        _notified(run, sender, account, serials, check, {'A': True, 'B': True})
        sync.set('checked')

    def hold(said, sync):
        _after(sync, 'checked', 'B')

    result, memo = two({('A', 'in'): a_in, ('A', 'hold'): hold, ('B', 'wait'): b_wait, ('B', 'in'): b_both},
                       a_job={'token_hash': run.link(account['email'])}, **LIMITS)
    return _verdict(check, result, memo)


# ── 65 한 기기 로그아웃 ────────────────────────────────────────────────────────────────────────────

def push_65(run, two):
    """A 폰이 로그아웃하면 push_tokens 는 B 에뮬 것 1행만 남고 알림은 A 0 · B 1 이며 B 는 로그인을 유지한다.
    근거: sign_out.dart(gotrue signOut 기본 local) · 로그아웃은 그 기기 토큰만 지운다. A 의 "0" 은 같은 읽기가 B 에서 알림을 읽는 것으로 살아 있음을 본다."""
    check, seen = Check(), {}
    account, serials, sender = _setup(run, two, push=True)
    a_in, b_wait, b_in = _joined(run, account, check, seen)

    def both(said, sync):
        _after(sync, 'both-in', 'B')

    def out(said, sync):
        _wait(lambda: len(_tokens(run, account['id'])) <= 1, GONE_WAIT)
        left = {row['token'] for row in _tokens(run, account['id'])}
        check.that(left == seen.get('b'), f'A 가 로그아웃한 뒤 push_tokens {left} — B 에뮬의 것 {seen.get("b")} 1행만 남아야 함')
        _notified(run, sender, account, serials, check, {'A': False, 'B': True})
        sync.set('done')

    def b_ready(said, sync):
        b_in(said, sync)
        sync.set('both-in')

    def stay(said, sync):
        _after(sync, 'done', 'A')

    result, memo = two({('A', 'in'): a_in, ('A', 'both'): both, ('A', 'out'): out,
                        ('B', 'wait'): b_wait, ('B', 'in'): b_ready, ('B', 'stay'): stay},
                       a_job={'token_hash': run.link(account['email'])}, **LIMITS)
    return _verdict(check, result, memo, 'A 에서 "0" 은 읽기가 깨진 것과 구별이 안 되나 같은 읽기가 B 에서 알림을 읽는다')


# ── 71 탈퇴 ────────────────────────────────────────────────────────────────────────────────────────

def push_71(run, two):
    """A 폰이 탈퇴하면 그 계정의 push_tokens 가 모두 지워지고(A 행 0) B 에뮬도 로그인 화면으로 돌아간다(앱이 세션 새로고침을 앞당겨 부른다).
    근거: account/router.py:31-33 · account/repository.py:113-117."""
    check, seen = Check(), {}
    account, _, _ = _setup(run, two, push=False)
    a_in, b_wait, b_in = _joined(run, account, check, seen)

    def both(said, sync):
        _after(sync, 'both-in', 'B')

    def withdrawn(said, sync):
        _wait(lambda: not _tokens(run, account['id']), TOKEN_WAIT)
        left = _tokens(run, account['id'])
        check.that(not left, f'탈퇴했는데 push_tokens {left} 가 남음 — 0행이어야 함')
        sync.set('withdrawn')

    def b_ready(said, sync):
        b_in(said, sync)
        sync.set('both-in')

    def stay(said, sync):
        _after(sync, 'withdrawn', 'A')

    result, memo = two({('A', 'in'): a_in, ('A', 'both'): both, ('A', 'withdrawn'): withdrawn,
                        ('B', 'wait'): b_wait, ('B', 'in'): b_ready, ('B', 'stay'): stay},
                       a_job={'token_hash': run.link(account['email'])}, **LIMITS)
    return _verdict(check, result, memo, '"알림 0" 은 안 봄(탈퇴한 계정에는 알림을 보낼 수 없다) · B 는 스스로 알아채는 시간(최대 1시간)이 아니라 새로고침을 앞당겨 본 것')


# ── 등록 · 묶음 ────────────────────────────────────────────────────────────────────────────────────

CASES = {'E-PUSH-64': push_64, 'E-PUSH-65': push_65, 'E-PUSH-71': push_71}
TWO = dict(CASES)

twodev.TWO.update(TWO)
area1.BUNDLES['area4-push-two'] = list(CASES)
for _case in CASES:
    tools.CASE_LIMITS[_case] = CASE_LIMIT
