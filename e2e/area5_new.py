"""영역 5 새 5개(묶음 area5-new) — 폰 A: E-EDGE-12 · E-WD-19, B에뮬: E-EDGE-04 · E-WD-20 · E-EDGE-10(망 지연 · 망 끊기 · 시계는 에뮬에서만).
기대값은 바탕화면 E2E_최종테스트_시나리오.md 의 그 줄(10-04 갱신)을 지금 코드와 대조한 것이다. 앱 쪽은 frontend/integration_test/area5_new.dart 의
같은 번호(area5.dart 가 묶는다). 돌릴 때: `--device A` 로 한 번, `--device B` 로 한 번 — 에뮬이 아니면 에뮬 셋은 blocked. E-EDGE-12 는 어느 기기든 돈다.
E-EDGE-10 이 adb root 를 남기므로 묶음 맨 끝이다(area5_edge 의 E-EDGE-25 와 같다). 쓰기는 이번 실행이 만든 계정에만(area2._guard).
운영 배치(chat-gate · cleanup)는 부르지 않는다. 디스코드 0줄(신고 · 하트 인증 · 학생증 길을 안 부른다).

기기 설정은 어떤 끝(예외 · blocked · 시간 상한)에서도 되돌린다 — 에뮬 망 지연은 `network delay none` · `speed full`, 끊은 망은 emu.go_online,
비행기 모드는 area2_phone3.offline, 시계는 emu.clock_shifted, 글자 배율은 [font_scaled](원래 값, 없었으면 1.0).

유료(OpenAI 이미지): E-EDGE-04 만 — 요청이 서버에 닿으면 워커가 아바타를 만든다. area5_act._paid_case 로 E2E_REAL_AI=1 일 때만, 앱이 켜진 뒤에는 한 번만
(fail 이면 러너가 다시 불러도 첫 결과를 돌려준다). 계정 공장의 온보딩(Vision · 임베딩)은 다른 가설과 같고 이 문으로 막지 않는다.

시나리오와 다르게 도는 것(보고의 "확인 필요"):
  E-EDGE-04  "누른 뒤 1초" 는 앱이 누르자마자 보낸 말(답을 안 기다린다)을 PC 가 받은 때부터 잰다 — 우편함 왕복만큼 늦다. 망은 svc wifi · data 로 끊는다.
             "변환 중 유지" 는 안내가 망이 돌아온 때(누른 뒤 1 + 10초)보다 늦게 사라졌는지로 본다(앱이 누른 때부터 안내가 사라진 때까지 ms 를 말한다).
             요청이 닿았는지는 새 아바타 행으로 가른다 — 닿았으면 완성(ready) · 새 그림 · 하트 그대로(무료 차례), 안 닿았으면 결과 기록(pass 메모).
  E-EDGE-10  서버 관문은 요청마다 GoTrue /user 로 세션을 묻는다(student_verification/current_user.py) — logout scope=global 뒤에는 들고 있던 토큰도
             곧바로 거절돼, 시나리오의 "즉시 저장은 성공" 이 아니라 첫 저장부터 401 → 토큰 새로 받기 실패 → 02 + "세션이 만료됐어요"(A11) 다.
             그래서 PC 가 끊은 뒤 GoTrue /user 를 직접 물어(area5_wd._sessions_cut) 끊겼으면 그 길을, 살아 있으면 시나리오 길(저장 성공 → 에뮬 시계
             +65분 → 아무 탭 → 60초 안에 02)을 기대값으로 쓴다. 시계는 끊기지 않은 길에서만 옮긴다(root 는 처음에 확인 — 없으면 blocked).
             시계를 넘긴 뒤 02 의 알림은 10-04 "확인 필요"(gotrue 가 스스로 새로고침하다 세션을 먼저 지울 수 있다)라 판정하지 않고 메모로 남긴다.
  E-EDGE-12  화면은 지시서의 일곱(15 · 15-4 · 15-5 · 06-1 · 15-6 · 15-6-2 · 15-7) — 시나리오의 15b 시트 · 15c · 16c 두 시트는 이 가설에 없다.
             15-6-2(닉네임 잠김)는 PC 가 잠금을 풀어 15-6 을 본 뒤, 앱이 멈춘 사이 nickname_changed_at 을 지금으로 바꾸고 앱이 내 프로필을 다시 읽어 연다.
             앱이 FlutterError 를 모아 넘침("overflowed")마다 (화면, 위치)를 말한다 — 위치는 "relevant error-causing widget" 의 frontend/lib 파일:줄.
             알려진 깨짐(백로그 57)은 06-1 의 얼굴상 칸(appearance_pickers.dart) 1.3배부터 · MBTI 토글(mbti_pole_toggle.dart) 2.0배 — 파일 이름으로
             가른다(인상 칸도 같은 파일이라 같이 "알려진 것" 이 된다). 그 밖의 넘침은 fail. 글자 잘림은 사람 몫이라 보지 않는다.
             배율은 앱이 MediaQuery.textScaler.scale(8)/8 로 읽어 ±0.1 이 아니면 blocked(안드로이드 14 의 비선형 확대는 작은 글자에서 선형이다).
  E-WD-19    "인터넷 켜고 다시 누르면 E-WD-04 와 같음" 까지 한다 — 두 번째 누름의 02 · 알림 · status · 재가입 제한 한 행을 E-WD-04 처럼 본다.
  E-WD-20    망 지연은 지시서대로 5초(시나리오 2초). "서버 요청 1건" 은 Cloud Run 로그가 아니라 DB 로 본다(지시서) — withdrawn 한 번 · 새 제한 행 1 ·
             withdrawn_at = 첫 누름 ±60초. 두 번째 요청이 갔어도 첫 탈퇴가 로그인을 끊어 401 로 끝나 DB 로는 안 갈린다 — 한 번만 갔다는 주된 증거는
             두 번째 누름 때 버튼이 꺼져 있었다(AppButton.onPressed == null, isSubmitting)는 앱의 말이다.
"""

import contextlib
import time
from datetime import datetime, timedelta, timezone

from e2e import area1, area2, emu, tools
from e2e.area1 import Check, _app
from e2e.area1_b2 import _blocks
from e2e.area2_phone3 import AI_WAIT, _balance, _slow, offline
from e2e.area3_phone import MISSING
from e2e.area4 import _restore, stepper
from e2e.area5_act import _cut_settled, _paid_case, _profile, _set, _unlock, _write
from e2e.area5_edge import NETWORK, NEW_HEIGHT, OLD_HEIGHT, _emu, _net_normal, _walk
from e2e.area5_read import TITLES, _avatar_rows, _home, _ready_avatars
from e2e.area5_wd import EXPIRED, LOGIN_MS, ROOM, WITHDRAWN, _notice, _reached_login, _sessions_cut, _state, _tapped, _withdrawn
from e2e.tools import Blocked

APP_WAIT = 180  # Run.phone 이 앱의 말 하나를 기다리는 초(기본값)
REGEN_DELAY_MS = 5000  # 시나리오 E-EDGE-04 "망 지연 5초"
CUT_AFTER, OFFLINE = 1, 10  # E-EDGE-04 "누른 뒤 1초에 끊고 10초 뒤 켬"
CUT_CHECK = 6  # 끊은 뒤 핑이 멎기를 기다리는 초 — 10초 단절 안에서 잰다
HOLD_MS =(CUT_AFTER + OFFLINE) * 1000  # 변환 중 안내가 적어도 이때까지 떠 있어야 한다(망이 돌아온 때)
WORKER_WAIT = AI_WAIT + 420  # 앱이 워커를 기다리는 시간(초) — 앱은 11분까지 본다(area5_photo.WORKER_WAIT 와 같다)
SHIFT = timedelta(minutes=65)  # E-EDGE-10 에뮬 시계
CLOCK_LOGIN_MS = 60_000  # E-EDGE-10 "시계를 넘긴 뒤 60초 안에 02"
SCALES = (1.3, 2.0)  # E-EDGE-12
SCREENS = ['15', '15-4', '15-5', '06-1', '15-6', '15-6-2', '15-7']
KNOWN = (('06-1', 'appearance_pickers.dart', 1.3), ('06-1', 'mbti_pole_toggle.dart', 2.0))  # (화면, 파일, 이 배율부터) — 백로그 57
WD_DELAY_MS = 5000  # 지시서 E-WD-20 "5초 지연"(시나리오 2초)


def _now():
    return datetime.now(timezone.utc)


# ── E-EDGE-04 응답만 놓친 다시 만들기 ─────────────────────────────────────────────────────────────────

def p_edge_04(run, phone, paid):
    serial = phone.serial
    emu.require_emulator(serial)
    check = Check()
    account, token = _home(run)
    ready = len(_ready_avatars(run, account))
    if ready != 1:
        raise Blocked(f'준비: ready 아바타 {ready}장 — 기대 1장(무료로 만드는 차례)')
    known = {r[0] for r in _avatar_rows(run, account)}
    balance = _balance(run, account)

    def slow(said):  # 앱이 15b 시트를 연 채 멈춤 — 망을 5초 늦춘다
        _emu(serial, 'network', 'delay', str(REGEN_DELAY_MS))

    def cut(said):  # 앱이 "무료로 만들기" 를 누르자마자 말함 — 1초 뒤 끊고 10초 뒤 켠다
        time.sleep(CUT_AFTER)
        emu.net(serial, False)
        started = time.monotonic()
        if not emu.wait_net(serial, False, timeout=CUT_CHECK):  # 안 끊겼는데 지나가면 "응답만 놓친 길" 을 안 본 채 pass 가 된다
            emu.go_online(serial)
            raise Blocked(f'망을 끊지 못함(svc wifi · data 뒤 {CUT_CHECK}초 동안 핑이 계속 닿음)')
        time.sleep(max(0.0, OFFLINE - (time.monotonic() - started)))
        if not emu.go_online(serial):
            raise Blocked('망을 다시 켰는데 닿지 않음')

    paid()  # 여기부터는 큐 등록 · OpenAI 이미지 생성(유료)이 나갈 수 있다
    try:
        said = _app(check, _slow(phone, WORKER_WAIT)(midway=stepper(phone, slow, cut), token_hash=token))
    finally:
        try:
            _net_normal(serial)
        finally:
            emu.go_online(serial)
    new = [r[1] for r in _avatar_rows(run, account) if r[0] not in known]
    if 'failed' in new:
        raise Blocked(f'아바타 생성이 실패(AI 쪽) — 앱 결함으로 세지 않는다(새 행 {new})')
    if 'pending' in new:
        raise Blocked(f'워커가 {WORKER_WAIT}초 안에 안 끝남(새 행 {new}) — 판정 못 함')
    check.that(said.get('generating_seen') is True, f"\"아바타로 변환 중이에요\" 안내 {said.get('generating_seen', MISSING)}(기대 보임)")
    check.that(said.get('failed_toast') is False, f"15-3 실패 안내 {said.get('failed_toast', MISSING)}(기대 0번 — 응답을 놓친 것은 실패가 아니다)")
    ms = said.get('generating_ms', MISSING)
    check.that(ms is None or (isinstance(ms, int) and ms >= HOLD_MS), f'변환 중 안내가 누른 뒤 {ms}ms 에 사라짐(기대 망이 돌아온 {HOLD_MS}ms 뒤까지 유지)')
    state, changed = said.get('regen_state', MISSING), said.get('avatar_changed', MISSING)
    if not new:
        return check.result(f'요청이 서버에 안 닿음(새 아바타 행 0) — 결과 기록: 상태 {state!r} · 그림 바뀜 {changed} · 변환 중 {ms}ms. 유료 호출 0번')
    check.that(new == ['ready'], f'새 아바타 행 {new}(기대 완성 1개)')
    check.that(changed is True, f'히어로 그림이 새 그림으로 바뀜 {changed}(기대 True — 서버에 닿았다)')
    check.that(state == 'ready', f'다시 만들기 상태 {state!r}(기대 ready)')
    have = _balance(run, account)
    check.that(have == balance, f'하트 {have}(기대 {balance} 그대로 — 첫 다시 만들기는 무료)')
    return check.result(f'요청이 서버에 닿음(새 아바타 행 1) — 응답만 놓친 길. 변환 중 {ms}ms. 유료 호출: 큐 등록 1번 · OpenAI 이미지 1번')


# ── E-EDGE-10 다른 곳에서 세션을 전부 끊음 ───────────────────────────────────────────────────────────

def _logout_everywhere(run, account):
    """이 사람의 로그인을 모두 끊는다 — 앱의 세션도 같이 끊긴다(scope=global)."""
    area2._guard(run, account['id'])
    status = tools.call('POST', f"{run.cfg['SUPABASE_URL']}/auth/v1/logout?scope=global",
                        {'apikey': run.cfg['SUPABASE_ANON_KEY'], 'Authorization': f"Bearer {account['token']}"})[0]
    if status >= 300:
        raise Blocked(f'logout scope=global {status}')


def p_edge_10(run, phone):
    serial = phone.serial
    emu.require_emulator(serial)
    emu.root(serial, getattr(phone, 'hub', None))  # 시계를 옮길 수 있어야 한다 — 안 되면 계정을 만들기 전에 blocked
    check = Check()
    account, token = _home(run)
    _set(run, account, f'키 {OLD_HEIGHT}', height_cm=OLD_HEIGHT)
    seen = {}
    with contextlib.ExitStack() as clock:  # 앱이 끝나면(어떻게든) 시계를 되돌린다
        def opened(screen):  # 앱이 15-6 을 연 채 멈춤
            _logout_everywhere(run, account)
            seen['cut'] = _sessions_cut(run, account)

        def saved(screen):  # 저장이 됐고 로그인이 살아 있음 — 시계를 넘긴다
            clock.enter_context(emu.clock_shifted(serial, SHIFT.total_seconds() / 3600))
            seen['shifted'] = True
        said = _app(check, phone(midway=_walk(phone, {'opened': opened, 'saved': saved}), token_hash=token, height=NEW_HEIGHT))
    if 'cut' not in seen:
        check.that(False, '앱이 15-6 에서 멈추지 않고 끝남 — 세션을 끊지 못했다')
        return check.result()
    height = _profile(run, account, 'height_cm').get('height_cm')
    if seen['cut']:
        check.that(said.get('login_after_save') is True, f"끊긴 세션의 저장 뒤 02 {said.get('login_after_save', MISSING)}(기대 닿음 — 서버가 세션을 묻는다)")
        check.that(said.get('notice', MISSING) == EXPIRED, f"02 알림 {said.get('notice', MISSING)!r}(기대 {EXPIRED!r})")
        check.that(height == OLD_HEIGHT, f'DB 키 {height}(기대 {OLD_HEIGHT} 그대로)')
        return check.result('시나리오와 다름: 서버 관문이 요청마다 GoTrue /user 로 세션을 묻어 logout scope=global 뒤 첫 저장부터 401 → 02 + 세션 만료(A11). '
                            '"토큰이 끝날 때까지 된다" 는 길이 없어 시계 +65분은 쓰지 않았다')
    check.that(said.get('saved_title', MISSING) == TITLES['15-5'], f"즉시 저장 뒤 화면 {said.get('saved_title', MISSING)!r}(기대 {TITLES['15-5']!r})")
    check.that(height == int(NEW_HEIGHT), f'DB 키 {height}(기대 {NEW_HEIGHT})')
    check.that(seen.get('shifted') is True, '앱이 저장 뒤 멈추지 않아 시계를 못 넘김')
    ms = said.get('login_ms', MISSING)
    check.that(isinstance(ms, int) and ms <= CLOCK_LOGIN_MS, f'시계 +65분 뒤 02 까지 {ms}ms(기대 {CLOCK_LOGIN_MS}ms 안)')
    return check.result(f"세션이 끊기지 않은 서버 — 저장 성공 → 시계 +65분 → 02 {ms}ms · 02 알림 {said.get('late_notice', MISSING)!r}(10-04 확인 필요 — 판정 안 함)")


# ── E-EDGE-09 시계를 넘긴 뒤 저장 ────────────────────────────────────────────────────────────────────

def p_edge_09(run, phone):
    """15-6 을 연 채 에뮬 시계 +65분 → 30초 뒤 "저장" → 첫 누름에 저장되어 15-5 로, "세션이 만료됐어요" 0번 · 02 0번. 서버 기준 토큰이 안 끝났으면 첫 요청이 그대로 200 이어도
    통과 조건은 같다(시나리오 10-04 갱신 — A11: 401 이면 토큰을 새로 받아 한 번 더 보낸다). 에뮬 root 가 필요하니 E-EDGE-10 과 같이 묶음 끝이다."""
    serial = phone.serial
    emu.require_emulator(serial)
    emu.root(serial, getattr(phone, 'hub', None))  # 시계를 옮길 수 있어야 한다 — 안 되면 계정을 만들기 전에 blocked
    check = Check()
    account, token = _home(run)
    _set(run, account, f'키 {OLD_HEIGHT}', height_cm=OLD_HEIGHT)
    seen = {}
    with contextlib.ExitStack() as clock:  # 앱이 끝나면(어떻게든) 시계를 되돌린다
        def opened(screen):  # 앱이 15-6 을 연 채 멈춤 — 시계를 넘긴다
            clock.enter_context(emu.clock_shifted(serial, SHIFT.total_seconds() / 3600))
            seen['shifted'] = True
        said = _app(check, phone(midway=_walk(phone, {'opened': opened}), token_hash=token, height=NEW_HEIGHT))
    if not seen.get('shifted'):
        check.that(False, '앱이 15-6 에서 멈추지 않고 끝남 — 시계를 못 넘김')
        return check.result()
    height = _profile(run, account, 'height_cm').get('height_cm')
    check.that(said.get('expired_seen') is False, f"'{EXPIRED}' 알림이 뜬 적 {said.get('expired_seen', MISSING)}(기대 0번)")
    check.that(said.get('login_seen') is False, f"로그인 화면(02)에 간 적 {said.get('login_seen', MISSING)}(기대 0번)")
    check.that(said.get('saved_title', MISSING) == TITLES['15-5'], f"저장 뒤 화면 {said.get('saved_title', MISSING)!r}(기대 {TITLES['15-5']!r})")
    check.that(height == int(NEW_HEIGHT), f'DB 키 {height}(기대 {NEW_HEIGHT} — 첫 누름에 저장)')
    return check.result('서버 기준 토큰이 안 끝났으면 첫 요청이 그대로 200 이었을 수 있다 — 어느 길이든 통과 조건은 같다. 에뮬 시계는 끝나면 PC 시계로 되돌린다')


# ── E-EDGE-12 큰 글자에서 넘침 ───────────────────────────────────────────────────────────────────────

def _font(serial):
    return tools.adb(serial, 'shell', 'settings', 'get', 'system', 'font_scale', check=False).strip()


@contextlib.contextmanager
def font_scaled(serial, scale):
    """기기 글자 배율을 [scale] 로 — 끝나면(실패해도) 원래 값(없었으면 1.0). 앱은 이 안에서 새로 켜야 먹는다(Run.phone 이 새로 켠다)."""
    before = _font(serial)
    try:
        float(before)
    except ValueError:
        before = '1.0'
    try:
        tools.adb(serial, 'shell', 'settings', 'put', 'system', 'font_scale', str(scale), check=False)
        if _font(serial) != str(scale):
            raise Blocked(f'글자 배율을 {scale} 로 못 바꿈(settings put system font_scale) — 지금 {_font(serial)!r}')
        yield
    finally:
        tools.adb(serial, 'shell', 'settings', 'put', 'system', 'font_scale', before, check=False)


def _known(row, scale):
    return any(row.get('screen') == screen and name in (row.get('where') or '') and scale >= since for screen, name, since in KNOWN)


def p_edge_12(run, phone):
    check = Check()
    account, _ = _home(run)
    marked = []
    for scale in SCALES:
        _unlock(run, account)  # 15-6 은 풀린 채, 15-6-2 는 앱이 멈춘 사이 잠근다
        with font_scaled(phone.serial, scale):
            said = _app(check, phone(midway=lambda said: _write(run, account, {'nickname_changed_at': _now().isoformat()}),
                                     token_hash=run.link(account['email']), scale=scale), f'{scale}배')
        check.that(said.get('visited', MISSING) == SCREENS, f"{scale}배: 연 화면 {said.get('visited', MISSING)}(기대 {SCREENS})")
        check.that(said.get('locked') is True, f"{scale}배: 15-6-2 닉네임 잠김 {said.get('locked', MISSING)}(기대 True)")
        for row in said.get('overflows') or []:
            line = f"{row.get('screen')} {row.get('where')}"
            if _known(row, scale):
                marked.append(f'{scale}배 {line}')
            else:
                check.that(False, f'{scale}배: 넘침 {line}(기대 0건)')
    known = f"알려진 것(백로그 57): {', '.join(marked)}" if marked else '알려진 깨짐도 안 나옴'
    return check.result(f'넘침만 자동 — 글자 잘림은 사람 몫. {known}')


# ── E-WD-19 끊긴 망에서 탈퇴 ─────────────────────────────────────────────────────────────────────────

def p_wd_19(run, phone):
    check = Check()
    account, token = _home(run)
    before = _blocks(run)
    mid = {}

    def failed(said):  # 끊긴 망에서 누른 뒤 — 탈퇴되지 않았는지 보고 망을 되돌린다
        mid.update(state=_state(run, account), blocks=_blocks(run))
        _restore(phone)(said)
    said = offline(phone, check, _cut_settled(phone), failed, token_hash=token)
    status = (mid.get('state') or {}).get('status', MISSING)
    check.that(status == 'active', f'망이 끊긴 채 누른 뒤 status {status!r}(기대 active)')
    check.that(mid.get('blocks', before) == before, '망이 끊긴 채 누른 뒤 재가입 제한 행이 생김(기대 그대로)')
    check.that(said.get('error', MISSING) == NETWORK, f"시트 안 문구 {said.get('error', MISSING)!r}(기대 {NETWORK!r})")
    check.that(said.get('sheet_open') is True, f"문구 뒤 최종 시트 {said.get('sheet_open', MISSING)}(기대 열린 채)")
    check.that(said.get('login_seen') is False, f"끊긴 망에서 02 로 감 {said.get('login_seen', MISSING)}(기대 안 감)")
    _notice(check, said, WITHDRAWN)
    _reached_login(check, said, LOGIN_MS)
    _withdrawn(check, run, account, before, _tapped(check, said))
    return check.result('망을 되돌린 뒤 다시 누름까지 — E-WD-04 와 같은 02 · 알림 · status · 재가입 제한을 본다')


# ── E-WD-20 느린 망에서 두 번 누르기 ─────────────────────────────────────────────────────────────────

def p_wd_20(run, phone):
    emu.require_emulator(phone.serial)
    check = Check()
    account, token = _home(run)
    before = _blocks(run)
    try:
        said = _app(check, phone(midway=lambda said: _emu(phone.serial, 'network', 'delay', str(WD_DELAY_MS)), token_hash=token))
    finally:
        _net_normal(phone.serial)
    check.that(said.get('second_blocked') is True, f"0.2초 뒤 두 번째 누름 때 버튼 꺼짐 {said.get('second_blocked', MISSING)}(기대 True — isSubmitting)")
    _notice(check, said, WITHDRAWN)
    _reached_login(check, said)
    _withdrawn(check, run, account, before, _tapped(check, said))
    return check.result(f'망 지연 {WD_DELAY_MS}ms. 탈퇴 호출 수는 DB(withdrawn 한 번 · 새 제한 행 1 · withdrawn_at = 첫 누름 ±60초)와 꺼진 버튼으로 봤다 — '
                        '두 번째 요청은 갔어도 401 이라 DB 로는 안 갈린다(시나리오는 Cloud Run 요청 로그 1건)')


PHONE = {
    'E-EDGE-04': _paid_case('E-EDGE-04', p_edge_04), 'E-EDGE-12': p_edge_12, 'E-WD-19': p_wd_19, 'E-WD-20': p_wd_20, 'E-EDGE-10': p_edge_10,
    'E-EDGE-09': p_edge_09,  # 10 · 09 는 adb root 를 남긴다 — 맨 끝
}
EMULATOR = ['E-EDGE-04', 'E-WD-20', 'E-EDGE-10', 'E-EDGE-09']  # --device B — 10 · 09 가 adb root 를 남기므로 맨 끝

area1.PHONE.update(PHONE)
area1.BUNDLES['area5-new'] = list(PHONE)
tools.CASE_LIMITS.update({
    'E-EDGE-04': WORKER_WAIT + ROOM,  # 워커 기다림(앱 11분) + 준비
    'E-EDGE-12': len(SCALES) * 2 * APP_WAIT + ROOM,  # 배율마다 앱 한 번(멈춤 하나)
    'E-WD-19': 3 * APP_WAIT + ROOM,  # 멈춤 둘 · 결과
    'E-WD-20': 2 * APP_WAIT + ROOM,  # 멈춤 · 5초 지연 결과
    'E-EDGE-10': 3 * APP_WAIT + ROOM,  # 멈춤 둘(끊기 · 시계) · 결과
    'E-EDGE-09': 3 * APP_WAIT + ROOM,  # 멈춤 · 30초 기다림 · 저장 · 끝 멈춤
})
