"""영역 5 가짜 서버 응답 가설 4개 — E-EDGE-05 · 06 · 07 · 08(묶음 area5-fake). 폰 A 한 대.
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 5 의 그 줄이되, 코드가 다르면 코드가 기준이다. 앱 쪽은 frontend/integration_test/area5_fake.dart 의 같은 번호.

서버가 502 · 500 · 429 를 주는 일은 운영 서버에서 만들 수 없으므로, 앱을 `apiClientProvider` 만 바꿔 끼워 다시 띄우고 정한 요청에만 가짜 응답을 준다(lib/ 는 안 바뀐다).
가짜가 대신 답한 요청은 서버에 닿지 않는다 — 그래서 DB 는 안 바뀌고 임베딩 · 이미지 생성(유료)도 안 나가며 `E2E_REAL_AI` 문이 필요 없다.
PC 는 그것을 두 가지로 확인한다: ① 앱이 말한 `faked`(대신 답한 요청)에 그 길이 상태코드와 함께 있는가 ② `passed`(가짜 없이 서버로 그냥 간 요청)에 그 길이 없는가.
탈퇴(POST /account/withdraw)는 앱 쪽 가짜가 규칙이 없어도 서버에 안 보낸다. 그래도 PC 는 끝에 status · withdrawn_at 이 그대로인지 본다.

E-EDGE-05  502(503 은 `_classify` 가 같은 길이라 502 만): 15-6 저장 · 15-7 저장 · 다시 만들기 토스트 · 영구 삭제 시트에 "잠시 뒤 다시 시도해 주세요", 화면 그대로, DB 변화 0.
E-EDGE-06  500: 같은 네 곳에 "알 수 없는 오류가 발생했습니다"(502 와 다르다).
E-EDGE-07  15 · 15-5 · 15-4 의 읽기(GET /me/profile · /me/card-preview)를 500 으로, 이어 502 로 — 둘 다 "잠시 뒤 다시 시도해 주세요" + "다시 시도", 가짜를 거두고 누르면 3초 안에 정상.
           비행기 모드(끊김) 쪽은 안 다룬다 — 이 가설 몫의 가짜 응답 부분만.
E-EDGE-08  429: 15-6 저장에 "너무 많이 시도했어요. 잠시 후 다시 시도해 주세요", DB 변화 0.
"""

from e2e import area1, tools
from e2e.area1 import Check, _app
from e2e.area2_phone3 import _balance
from e2e.area3_phone import MISSING
from e2e.area5_edge import NEW_HEIGHT, _prepare
from e2e.area5_read import TITLES, _home, _ready_avatars, _saved
from e2e.area5_wd import _state
from e2e.tools import Blocked

MESSAGE = {502: '잠시 뒤 다시 시도해 주세요', 500: '알 수 없는 오류가 발생했습니다', 429: '너무 많이 시도했어요. 잠시 후 다시 시도해 주세요'}
LOAD_FAIL = '잠시 뒤 다시 시도해 주세요'  # me_load_error.dart — 상태코드와 상관없이 한 문구
RECOVER_MS = 3000  # 시나리오 07 "누르면 3초 안에 정상"
ROUTES = {'15-6': 'PATCH /me/profile', '15-7': 'PUT /me/photos', 'avatar': 'POST /me/avatar/regenerate', 'withdraw': 'POST /account/withdraw'}
READS = {'15': 'GET /me/profile', '15-5': 'GET /me/profile', '15-4': 'GET /me/card-preview'}
PLACES = ['15-6', '15-7', 'avatar', 'withdraw']
CASE_LIMIT = 900


def _hit(entries, route, status=None):
    """앱이 말한 요청 목록(`METHOD /경로` · 대신 답한 것은 `=상태` 가 붙는다)에 [route] 가 있는가 — 경로 앞에 붙은 접두는 무시한다."""
    method, path = route.split(' ')
    tail = path if status is None else f'{path}={status}'
    return any(entry.startswith(method + ' ') and entry.endswith(tail) for entry in entries)


def _faked(check, said, places, status, label):
    """대신 답한 요청이 [places] 의 길마다 한 번 이상 있고, 서버로 그냥 간 요청은 없다."""
    faked, passed = said.get('faked') or [], said.get('passed') or []
    for place in places:
        check.that(_hit(faked, ROUTES[place], status), f'{label}{place}: 가짜가 {ROUTES[place]} 에 {status} 를 대신 주지 않았다(대신 답한 요청 {faked})')
        check.that(not _hit(passed, ROUTES[place]), f'{label}{place}: {ROUTES[place]} 가 가짜를 지나 서버로 그냥 갔다(DB 가 바뀌었을 수 있다)')


def _saves(run, phone, status, places):
    check = Check()
    account, token = _home(run)
    _prepare(run, account)  # 키 178 · 관심사 4개 · 사진 2장 이상(15-7 에서 맞바꿀 것)
    if 'avatar' in places and len(_ready_avatars(run, account)) != 1:
        raise Blocked(f'준비: ready 아바타 {len(_ready_avatars(run, account))}장 — 기대 1장(무료로 만드는 차례)')
    before = {'saved': _saved(run, account), 'state': _state(run, account), 'balance': _balance(run, account)}
    said = _app(check, phone(token_hash=token, status=status, expect=MESSAGE[status], places=places, height=NEW_HEIGHT))
    walks = {walk.get('place'): walk for walk in said.get('walks') or []}
    for place in places:
        walk = walks.get(place, {})
        check.that(walk.get('error', MISSING) == MESSAGE[status], f"{place}: 문구 {walk.get('error', MISSING)!r}(기대 {MESSAGE[status]!r})")
        if place in ('15-6', '15-7'):
            check.that(walk.get('kept') is True, f"{place}: 고친 값이 그대로 {walk.get('kept', MISSING)}(기대 True)")
            check.that(walk.get('stayed', MISSING) == TITLES[place], f"{place}: 화면 {walk.get('stayed', MISSING)!r}(기대 그대로 {TITLES[place]!r})")
        elif place == 'withdraw':
            check.that(walk.get('sheet_open') is True and walk.get('login') is False,
                       f"withdraw: 시트 {walk.get('sheet_open', MISSING)} · 로그인 화면 {walk.get('login', MISSING)}(기대 시트 그대로 · 로그인 화면 아님)")
        else:
            check.that(walk.get('generating_gone') is True, f"avatar: 변환 중 안내가 안 사라짐 {walk.get('generating_gone', MISSING)}")
    _faked(check, said, places, status, '')
    after = {'saved': _saved(run, account), 'state': _state(run, account), 'balance': _balance(run, account)}
    for name, label in (('saved', '프로필 · 사진 · 아바타'), ('state', '계정 상태'), ('balance', '하트')):
        check.that(after[name] == before[name], f'DB {label} 가 바뀜(기대 변화 0): {before[name]} → {after[name]}')
    return check.result('가짜가 대신 답한 요청은 서버에 안 닿는다 — 유료 호출 0번 · 503 은 502 와 같은 길이라 안 돌림')


def p_edge_05(run, phone):
    return _saves(run, phone, 502, PLACES)


def p_edge_06(run, phone):
    return _saves(run, phone, 500, PLACES)


def p_edge_08(run, phone):
    return _saves(run, phone, 429, ['15-6'])


def p_edge_07(run, phone):
    check = Check()
    account, _ = _home(run)
    before = {'saved': _saved(run, account), 'state': _state(run, account)}
    for status in (500, 502):
        said = _app(check, phone(token_hash=run.link(account['email']), status=status), f'앱({status})')
        walks = {walk.get('place'): walk for walk in said.get('walks') or []}
        for place, route in READS.items():
            walk = walks.get(place, {})
            ms = walk.get('recovered_ms')
            check.that(walk.get('error', MISSING) == LOAD_FAIL, f"{status} {place}: 문구 {walk.get('error', MISSING)!r}(기대 {LOAD_FAIL!r})")
            check.that(walk.get('retry') is True, f"{status} {place}: '다시 시도' 버튼 {walk.get('retry', MISSING)}(기대 True)")
            check.that(isinstance(ms, int) and ms <= RECOVER_MS, f'{status} {place}: 가짜를 거두고 누른 뒤 정상까지 {ms}ms(기대 {RECOVER_MS}ms 이내)')
            check.that(_hit(said.get('faked') or [], route, status), f"{status} {place}: 가짜가 {route} 에 {status} 를 대신 주지 않았다(대신 답한 요청 {said.get('faked')})")
    after = {'saved': _saved(run, account), 'state': _state(run, account)}
    check.that(after == before, f'DB 가 바뀜(기대 변화 0): {before} → {after}')
    return check.result('끊김(비행기 모드)은 안 다룸 — 가짜 응답 부분만')


PHONE = {'E-EDGE-05': p_edge_05, 'E-EDGE-06': p_edge_06, 'E-EDGE-07': p_edge_07, 'E-EDGE-08': p_edge_08}

area1.PHONE.update(PHONE)
area1.BUNDLES['area5-fake'] = list(PHONE)
tools.CASE_LIMITS.update({case: CASE_LIMIT for case in PHONE})
