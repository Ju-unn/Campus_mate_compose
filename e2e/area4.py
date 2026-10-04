"""영역 4 알림 · 설정 — SET 1차: 설정 16 · 알림 설정 16d · 계정 16e · 카톡 16e-1 · 차단 목록 16f.
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 4 의 그 줄(10-04 갱신)이다. 앱 쪽은 frontend/integration_test/area4.dart 의 같은 번호.

`python -m e2e run area4-set1` 한 번으로 돈다(폰 A 한 대). 판정은 앱이 화면에서, DB 에 남은 것은 여기서 본다.
"""

from datetime import datetime, timedelta, timezone

from e2e import area1, notify
from e2e.area1 import Check, _app, _at, _on_phone, _one, _patch, _rows, _signed_in
from e2e.tools import Blocked
from e2e import tools

SEOUL = timezone(timedelta(hours=9))
# 16d 스위치 8개와 저장한 적 없을 때의 값(backend/app/cards/repository.py NOTIFICATION_DEFAULTS).
DEFAULTS = {'card_arrived': True, 'acceptance_received': True, 'match_made': True, 'new_message': True,
            'trust_reminder': True, 'new_friend_review': True, 'marketing': False, 'quiet_hours': True}
EMPTY = '—'

# 시나리오에 있지만 이 묶음에 안 넣은 것.
LEFT_OUT = {
    'E-SET-04': '배치를 불러 다음 카드가 안 나가는지까지 본다 — 배치 · 시간조작 묶음에서',
    'E-SET-26': '두 기기(A 가 B 를 차단 해제) — 두 기기 묶음에서',
    'E-SET-43': '배치 + 두 기기 — 배치 · 시간조작 묶음에서',
    'E-SET-53': '메일 앱이 없는 기기를 따로 만들어야 한다 — 에뮬 묶음에서',
    'E-SET-55': '운영 faq 표의 글을 고친다 — 모든 사용자에게 보이는 공개 표라 시험 규칙(테스트대학만)에 어긋난다(대장 10-04 skip)',
    'E-SET-56': '사람 필요 — 설정 약관 줄이 기기 브라우저로 열리는지는 대장이 사용자 폰으로 확인',
    'E-SET-57': '사람 필요 — 노션 약관 페이지 내용은 눈으로(대장이 사용자 폰으로 확인)',
    **{f'E-SET-{n:02d}': 'SET 2차(FAQ · 초대 · 로그아웃 · 탈퇴)에서' for n in (2, 3, *range(44, 53), 54, *range(58, 67), 68, 69, 70)},
}
# 기기 연락처를 넣고 빼는 가설 — 실폰에 연락처를 넣지 않는다(계획 4절 6항). 에뮬 묶음에서 코드로 만든다.
EMULATOR = [f'E-SET-{n}' for n in range(29, 43)]


def stepper(phone, *handlers):
    """앱이 `step` 을 말하고 멈출 때마다 [handlers] 를 차례로 부르는 midway. 첫 단계는 Run.phone 이 부르고,
    그다음부터는 여기서 go 를 넣고 다음 step 을 기다린다 — 마지막 go 는 Run.phone 이 넣는다(tools.py 를 안 고치고 두 번 멈추기)."""
    def midway(first):
        handlers[0](first)
        for number, handler in enumerate(handlers[1:], start=2):
            phone.hub.go()
            said = phone.hub.wait(120)
            if said is None or 'result' in said:
                raise Blocked(f'앱이 {number}번째 멈춤 전에 {"끝남" if said else "답하지 않음"}')
            handler(said)
    return midway


def _cut(phone):
    return lambda said: notify.airplane(phone.serial, True)


def _restore(phone):
    return lambda said: notify.airplane(phone.serial, False)


def _offline(phone, check, *stages, **job):
    """앱을 켠 뒤 [stages] 가 망을 끊고 켜는 동안 가설을 돈다. 어떻게 끝나든 망은 되돌린다 —
    중간에 이미 켰으면 아무것도 안 하고, 아직 꺼져 있으면 망이 돌아올 때까지 기다린다(다음 가설이 바로 로그인한다)."""
    try:
        return _app(check, phone(midway=stepper(phone, *stages), **job))
    finally:
        notify.ensure_online(phone.serial)


def _settings(run, account_id):
    return _one(run, f'notification_settings?profile_id=eq.{account_id}&select=*')


def _kakao(run, account_id):
    return _one(run, f'profile_private?profile_id=eq.{account_id}&select=kakao_id').get('kakao_id')


def _korean_date(text):
    return _at(text).astimezone(SEOUL).strftime('%Y.%m.%d')


# ── API 만 ─────────────────────────────────────────────────────────────────────────────────────

def set_08(run):
    """8개를 하나씩(기본값의 반대로) 바꿀 때마다 그 칸만 바뀌는지 — 서버 저장이 판정이라 폰이 필요 없다."""
    check = Check()
    account = run.account('home')
    expected = dict(DEFAULTS)
    for key, default in DEFAULTS.items():
        check.reply(key, tools.api(run.cfg, 'PATCH', '/cards/notification-settings', account['token'], {key: not default}), 200)
        expected[key] = not default
        row = _settings(run, account['id'])
        changed = sorted(k for k in DEFAULTS if row.get(k) != expected[k])
        check.that(not changed, f'{key} 를 바꾼 뒤 어긋난 칸 {changed}')
    return check.result()


# ── 설정 16 · 알림 설정 16d ───────────────────────────────────────────────────────────────────

def p_set_05(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    _patch(run, f"profiles?id=eq.{account['id']}", {'matching_paused': True})  # 04 의 화면 조작은 04 가 본다 — 여기는 저장된 값을 읽는지
    _app(check, phone(token_hash=token, paused=True))
    return check.result()


def p_set_06(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    _offline(phone, check, _cut(phone), token_hash=token)
    paused = _one(run, f"profiles?id=eq.{account['id']}&select=matching_paused").get('matching_paused')
    check.that(paused is not True, f'망이 없는데 matching_paused 가 {paused}')
    return check.result()


def p_set_07(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    if _settings(run, account['id']):
        raise Blocked('새 계정인데 notification_settings 행이 이미 있음')
    _app(check, phone(token_hash=token))
    return check.result()


def p_set_09(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    flips = ['new_message', 'marketing', 'quiet_hours']
    _app(check, phone(token_hash=token, flip=flips), '누름')
    expected = {key: (not value) if key in flips else value for key, value in DEFAULTS.items()}
    row = _settings(run, account['id'])
    got = {key: row.get(key) for key in DEFAULTS}
    check.that(got == expected, f'notification_settings {got}(기대 {expected})')
    _app(check, phone(fresh=False, switches=expected), '다시 켬')
    return check.result()


def p_set_10(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    _offline(phone, check, _cut(phone), token_hash=token)
    check.that(not _settings(run, account['id']), '망이 없는데 notification_settings 가 생김')
    return check.result()


# ── 계정 16e · 카톡 16e-1 ─────────────────────────────────────────────────────────────────────

def p_set_14(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    profile = _one(run, f"profiles?id=eq.{account['id']}&select=birth_year,created_at,universities(name)")
    private = _one(run, f"profile_private?profile_id=eq.{account['id']}&select=real_name,kakao_id")
    if not profile.get('created_at') or not (profile.get('universities') or {}).get('name'):
        raise Blocked(f'프로필을 못 읽음 {profile}')
    texts = [account['email'], '인증 완료', private.get('real_name') or EMPTY,
             str(profile['birth_year']) if profile.get('birth_year') else EMPTY, profile['universities']['name'],
             private.get('kakao_id') or EMPTY, _korean_date(profile['created_at'])]
    _app(check, phone(token_hash=token, texts=texts))
    return check.result()


def p_set_15(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    moment = datetime(2026, 3, 15, 0, 30, tzinfo=SEOUL)  # = UTC 전날 15:30
    _patch(run, f"profiles?id=eq.{account['id']}", {'created_at': moment.isoformat()})
    _app(check, phone(token_hash=token, date=moment.strftime('%Y.%m.%d')))
    return check.result()


def p_set_16(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    # 활성 계정은 출생연도가 비면 DB 제약(profiles_active_requires_onboarding)이 막는다 — 실명 · 카톡을 비워 "—" 2개를 만든다.
    _patch(run, f"profile_private?profile_id=eq.{account['id']}", {'real_name': None, 'kakao_id': None})
    _app(check, phone(token_hash=token, dashes=2))
    return check.result()


def p_set_17(run, phone):
    check = Check()
    _, token = _signed_in(run, 'home')
    _offline(phone, check, _cut(phone), _restore(phone), token_hash=token)
    return check.result()


def _kakao_job(**extra):
    """16e-1 을 여는 가설 — 앱이 저장하는 값은 일감 [value], 판정은 앱(화면)과 여기(DB)가 나눠 한다."""
    def case(run, phone):
        check = Check()
        account, token = _signed_in(run, 'home')
        _app(check, phone(token_hash=token, kakao=_kakao(run, account['id']), value=f"e2e{account['n']}x", **extra))
        return check.result()
    return case


def p_set_19(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    value = f"e2e{account['n']}x"
    _app(check, phone(token_hash=token, kakao=_kakao(run, account['id']), value=value))
    got = _kakao(run, account['id'])
    check.that(got == value, f'profile_private.kakao_id {got!r}(기대 {value!r})')
    return check.result()


def p_set_20(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    before = _kakao(run, account['id'])
    _app(check, phone(token_hash=token, kakao=before))
    after = _kakao(run, account['id'])
    check.that(after == before, f'저장 버튼이 꺼져 있어야 하는데 kakao_id 가 {before!r} → {after!r}')
    return check.result()


def p_set_21(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    value = f"  e2e{account['n']}t  "
    _app(check, phone(token_hash=token, kakao=_kakao(run, account['id']), value=value))
    got = _kakao(run, account['id'])
    check.that(got == value.strip(), f'kakao_id {got!r}(기대 {value.strip()!r})')
    return check.result()


def p_set_22(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    before = _kakao(run, account['id'])
    _offline(phone, check, _cut(phone), token_hash=token, kakao=before, value=f"e2e{account['n']}x")
    after = _kakao(run, account['id'])
    check.that(after == before, f'망이 없는데 kakao_id 가 {before!r} → {after!r}')
    return check.result()


def p_set_23(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    before = _kakao(run, account['id'])
    _app(check, phone(token_hash=token, kakao=before, value=f"e2e{account['n']}x"))
    after = _kakao(run, account['id'])
    check.that(after == before, f'저장 안 하고 뒤로 갔는데 kakao_id 가 {before!r} → {after!r}')
    return check.result()


# ── 차단 목록 16f ────────────────────────────────────────────────────────────────────────────

def _blocked_by(run, count):
    """A(폰) 가 [count] 명을 차단한 상태 — 상대는 홈 계정. (A, 로그인 토큰, 상대 닉네임들)."""
    account, token = _signed_in(run, 'home')
    others = [run.account('basic') for _ in range(count)]  # 16f 는 닉네임 · 아바타(없으면 비움)만 쓴다 — 온보딩 끝까지 갈 필요 없다
    status, body = tools.rest(run.cfg, run.key, 'POST', 'blocks',
                              [{'blocker_id': account['id'], 'blocked_id': other['id']} for other in others])
    if status >= 300:
        raise Blocked(f'blocks 넣기 {status} {body}')
    nicknames = [_one(run, f"profiles?id=eq.{other['id']}&select=nickname").get('nickname') for other in others]
    return account, token, nicknames


def _block_rows(run, account_id):
    return _rows(run, f'blocks?blocker_id=eq.{account_id}&select=blocked_id')


def _today():
    """차단일 글자 후보 — 앱이 UTC 날짜로 그리는지 한국 날짜로 그리는지 코드만으로 못 가려 둘 다 받는다(자정 근처에 갈린다)."""
    now = datetime.now(timezone.utc)
    return sorted({now.strftime('%Y.%m.%d'), now.astimezone(SEOUL).strftime('%Y.%m.%d')})


def p_set_25(run, phone):
    check = Check()
    _, token, nicknames = _blocked_by(run, 2)
    _app(check, phone(token_hash=token, nicknames=nicknames, dates=_today()))
    return check.result()


def p_set_27(run, phone):
    check = Check()
    account, token, nicknames = _blocked_by(run, 2)
    _app(check, phone(token_hash=token, nicknames=nicknames))
    rows = _block_rows(run, account['id'])
    check.that(len(rows) == 2, f'취소했는데 blocks {len(rows)}행')
    return check.result()


def p_set_28(run, phone):
    check = Check()
    account, token, nicknames = _blocked_by(run, 1)
    _app(check, phone(token_hash=token, nicknames=nicknames))
    rows = _block_rows(run, account['id'])
    check.that(not rows, f'해제했는데 blocks {len(rows)}행')
    return check.result()


PHONE = {
    'E-SET-01': _on_phone('home'), 'E-SET-05': p_set_05, 'E-SET-06': p_set_06, 'E-SET-07': p_set_07, 'E-SET-09': p_set_09,
    'E-SET-10': p_set_10, 'E-SET-11': _on_phone('home'), 'E-SET-13': _on_phone('home'),
    'E-SET-14': p_set_14, 'E-SET-15': p_set_15, 'E-SET-16': p_set_16, 'E-SET-17': p_set_17,
    'E-SET-18': _kakao_job(), 'E-SET-19': p_set_19, 'E-SET-20': p_set_20, 'E-SET-21': p_set_21,
    'E-SET-22': p_set_22, 'E-SET-23': p_set_23,
    'E-SET-24': _on_phone('home'), 'E-SET-25': p_set_25, 'E-SET-27': p_set_27, 'E-SET-28': p_set_28,
}
CASES = {'E-SET-08': set_08}

area1.PHONE.update(PHONE)
area1.CASES.update(CASES)
area1.BUNDLES['area4-set1'] = list(CASES) + list(PHONE)
