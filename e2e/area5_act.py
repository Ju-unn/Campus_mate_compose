"""영역 5 폰 A 한 대 — 나 탭에서 글 · 태그 · 조건 · 기본 정보를 고쳐 저장하는 16개(묶음 area5-act).
기대값은 바탕화면 E2E_시나리오_조각/5_나탭_탈퇴_경계.md 5-1 표의 그 줄을 지금 코드와 대조한 것이다.
앱 쪽은 frontend/integration_test/area5_act.dart 의 같은 번호(area5.dart 가 묶는다). 사진 · 아바타 8개는 이 묶음이 아니다(다음 PR).

가설 하나 = 함수 하나 `(run, phone) -> (결과, 메모)`. PC 가 홈 계정을 만들고 서비스 키 DB 로 준비하면, 앱이 화면을 열어 고쳐 저장하고(또는 저장하지 않고)
본 것을 Map 으로 말하고(문구는 사람이 읽는 글자 그대로, 못 본 것은 None — 이 쪽은 `MISSING` 과 가른다), 판정은 여기서 한다.
계정은 가설마다 새로 만든다. 쓰기는 이번 실행이 만든 계정에만 한다(`area2._guard`). 탈퇴 · 삭제 · 사진 흐름은 이 묶음에 없다.
서버에 직접 보내는 쓰기(ME-20 · 26 · 35 의 422 확인)는 두 번 적용돼도 되지만 한 번만 보낸다(`retry=False`).

유료(OpenAI 임베딩): `PATCH /me/profile` 은 bio 가 들어 있을 때만(me/router.py:233), `POST /profile-onboarding/ideal-conditions` 는 늘
refresh_vectors 를 불러 임베딩을 만든다. 그래서 앱이 자기소개를 저장하는 ME-07 · 18 과 이상형 조건을 저장하는 ME-24 · 25 는 `E2E_REAL_AI=1` 이 아니면
요청을 한 번도 보내지 않고 blocked 로 둔다(area2_phone3 의 real_ai_gate · _PAID, 앱이 켜진 뒤에는 한 번만). 키 · 닉네임 · 태그만 저장하는 가설(19 · 27 ·
34 · 35 와 태그를 저장하는 21)과 저장하지 않는 가설(20 · 23 · 26 · 31 · 33 · 36)은 임베딩을 안 부른다. (계정 공장의 온보딩도 같은 임베딩을 계정마다 부른다 —
그쪽은 이 문으로 막지 않는다.)

시나리오와 다르게 도는 것(보고의 "확인 필요"):
  E-ME-07       15c 저장은 15 가 아니라 15-5 로 돌아온다(편집 화면이 pop). 시나리오의 "뒤로 → 15" 는 앱이 15-5 에서 앱바 뒤로를 한 번 더 누르는 것이다.
                15-4 에서는 새 글을 찾는 낱말(고유 8자리)이 든 글자만 모아 [새 글] 과 같은지 본다(공장 학번 · 카톡 아이디와 안 겹친다).
  E-ME-18       "updated_at > 누른 시각" 은 PC 시계와 DB 시계가 달라 그대로 못 쓴다 — 앱을 켜기 전에 벡터 행의 시각을 하루 전, 문장 벡터를 단위벡터로 심어 두고
                (1) 시각이 앱을 켠 시각 − 120초 이후(안 건드렸다면 하루 전 값이라 걸린다) (2) 문장 벡터가 심은 값과 다름, 둘을 본다. 키만 고치는 ME-19 는 같은 행이 그대로.
  E-ME-21       6번째 칩은 5개를 고른 채 눌러 본다(안 골라져야 한다). 2개만 남기는 줄은 3개를 껐다가 같은 3개를 다시 켜 5개로 되돌린 뒤 저장한다.
                15c 칩은 관심사 · 나의 특징 · 이상형 특징 세 섹션 것이 한 목록이라 DB 세 칸을 이어 붙인 것과 견준다.
  E-ME-24 · 25  슬라이더는 손가락으로 끌지 않고 위젯의 onChanged 를 부른다(24~30). 끌기 자체는 사람이 실기기에서 본다. 24 의 "처음 값" 은 화면의 요약 글자
                ("22세 ~ 27세")로 읽는다.
  E-ME-26       얼굴상과 인상 둘 다 본다(시나리오는 얼굴상만). 서버 422 도 둘 다 — 이유 글자는 FastAPI 기본 문구의 "at most 3".
  E-ME-27 · 31 · 33 · 36  계정 공장은 04-1 저장 때 nickname_changed_at 을 now() 로 적는다(profile_onboarding/repository.py:39) — 새 계정은 처음부터 닉네임이 잠겨 있다.
                시나리오의 "nickname_changed_at = null" 은 PC 가 먼저 풀어 놓는다(서버 GET /me/profile 의 풀리는 때가 비었는지까지 확인). 새 닉네임은 매번 겹치지 않는
                한글 3자(계정 공장은 영문 5자)이고 PC 가 안 쓰는 이름인지 먼저 묻는다.
  E-ME-27       토스트 "저장했어요" 의 2초는 앱이 나타난 때부터 사라진 때까지 재서 1.5~3.5초면 통과.
  E-ME-31       15-6 을 연 앱이 `step` 에서 멈추면 PC 가 nickname_changed_at 을 지금으로 바꾼다. 앱이 그다음 새 닉네임을 쳐 저장하면 서버가 409 로 막고
                닉네임 칸 아래 오류 줄(경고 아이콘 + 오류색 글자)이 뜬다. 글자 색은 AppColors.error 의 값과 맞대 본다.
  E-ME-33       입력칸은 한글 · 영문 말고는 걸러 낸다(basic_info_screen.dart nicknameInputFormatters) — 시나리오의 "abc1" · "하늘!" 은 오류 문구가 아니라
                "abc" · "하늘" 이 되어 통과 문구가 뜬다. 판정은 앱이 보고한 칸 글자로 한다 — 금지 글자가 칸에 남으면 오류 문구 + 저장 꺼짐이어야 하고,
                걸러졌으면 남은 글자 기준으로 맞는지 본다(둘 다 시나리오가 막으려는 것은 막힌다). 통과 이름(abc · 하늘 · Sky)은 PC 가 먼저 안 쓰는지 묻는다.
  E-ME-35       "120 · 230 저장 성공" 은 저장 뒤 15-6 을 다시 열어 칸 글자가 그 값인지로 본다. 서버 300 → 422 는 DB check(profiles_height_range)가
                core/http.py 에서 422 "입력한 값을 다시 확인해 주세요" 로 바뀌는 것이다(me/schemas.py 는 키를 안 본다).
  E-ME-36       닉네임 되돌리기도 보려고 PC 가 잠금을 풀고 안 쓰는 다른 닉네임을 일감에 실어 준다.
"""

import random
import re
import time
import uuid
from datetime import datetime, timedelta, timezone
from urllib.parse import quote

from e2e import area1, area2, area4, tools
from e2e.area1 import Check, _api, _app, _at, _one, _patch, _rows
from e2e.area2_phone3 import _PAID, real_ai_gate, offline
from e2e.area3_phone import MISSING
from e2e.area4 import _cut, _restore
from e2e.area5_read import TITLES, _home, _server_unlock
from e2e.tools import Blocked

CUT_SETTLE = 2  # 비행기 모드를 켠 뒤 망이 정말 끊기기를 기다리는 초 — 켜자마자 앱이 치면 망이 아직 살아 있다(area5_edge.CUT_SETTLE 과 같은 이유 · 같은 값)
PLANT_AGO = timedelta(days=1)  # 벡터 행의 시각을 이만큼 옛날로 심는다 — PC · DB 시계 차이와 상관없이 "다시 만들었나" 가 갈린다
SKEW = timedelta(seconds=120)  # PC 시계와 DB 시계 차이 여유
TOAST_MS = (1500, 3500)  # "저장했어요" 토스트가 떠 있는 시간(약 2초, me_toast.dart MeToastHost.duration)
SYLLABLES = '가나다라마바사아자차카타파하'
NICKNAME = re.compile(r'^[가-힣a-zA-Z]{2,5}$')  # profile_onboarding/schemas.py NICKNAME_PATTERN
FILTERED = re.compile(r'[^가-힣a-zA-Zㄱ-ㅎㅏ-ㅣ]')  # 입력칸이 걸러 내는 글자(basic_info_screen.dart nicknameInputFormatters)
PROBES = ['가', '가나다라마바', 'abc1', '하늘!', '하늘', 'Sky']
FREE_NAMES = ('abc', '하늘', 'Sky')  # 통과해야 하는 이름 — 이미 쓰이는 이름이면 "통과" 를 못 본다
BAD_HEIGHTS, GOOD_HEIGHTS = ['119', '231'], ['120', '230']
INTERESTS = ['카페가기', '자전거', '패션', '반려동물']  # 서버 INTEREST_TAGS 안의 4개
EXTRA, SIXTH = '술', '산책'  # 하나 더 고를 것 · 6번째로 눌러 볼 것
INVALID = '입력한 값을 다시 확인해 주세요'  # core/errors.py INVALID_INPUT
AT_MOST_3 = 'at most 3'  # pydantic 의 max_length=3 위반 문구(profile_onboarding/schemas.py:76)
PREFS = 'preferred_age_min,preferred_age_max,preferred_height_min,preferred_height_max,preferred_animal_types,preferred_impression_types'
IDEAL_PREFS = {'preferred_age_min': 22, 'preferred_age_max': 27, 'preferred_height_min': 165, 'preferred_height_max': 180,
               'preferred_animal_types': ['dog', 'cat'], 'preferred_impression_types': ['kind']}
EMBEDDING = 512  # area2.EMBEDDING_DIMENSIONS


def _now():
    return datetime.now(timezone.utc)


# ── 준비 · 읽기 ──────────────────────────────────────────────────────────────────────────────────────

def _profile(run, account, columns):
    return _one(run, f"profiles?id=eq.{account['id']}&select={columns}")


def _write(run, account, fields):
    """이번 실행이 만든 계정의 프로필 칸을 바꾼다(가드)."""
    area2._guard(run, account['id'])
    _patch(run, f"profiles?id=eq.{account['id']}", fields)


def _set(run, account, label, **fields):
    """프로필 칸을 심고 다시 읽어 그 값이 맞는지 본다 — 안 바뀌었으면 "그대로" 가 증거가 못 되니 blocked."""
    _write(run, account, fields)
    got = _profile(run, account, ','.join(fields))
    if got != fields:
        raise Blocked(f'준비: {label}를 심지 못했다 — 읽은 값 {got}(기대 {fields})')


def _unlock(run, account, changed_at=None):
    """닉네임 잠금을 풀어 둔다(공장 계정은 04-1 저장 때 nickname_changed_at = now() 라 처음부터 잠겨 있다). [changed_at] 이 있으면 그 값."""
    _write(run, account, {'nickname_changed_at': changed_at.isoformat() if changed_at else None})
    unlock = _server_unlock(run, account)
    if unlock is not None:
        raise Blocked(f'준비: 닉네임 잠금이 안 풀렸다 — 서버가 준 풀리는 때 {unlock}')


def _free_nickname(run):
    """안 쓰는 한글 3자 — 계정 공장의 영문 5자와 겹칠 수 없다. 이미 있는지는 대소문자 무시로 PC 가 묻는다."""
    for _ in range(10):
        name = ''.join(random.choices(SYLLABLES, k=3))
        if not _rows(run, f'profiles?nickname=ilike.{quote(name)}&select=id'):
            return name
    raise Blocked('준비: 안 쓰는 닉네임을 10번 골라도 못 찾았다')


def _new_bio():
    """(새 자기소개, 그 안의 고유 낱말) — 공장 값(학번 · 카톡 아이디 · 옛 자기소개)과 겹치지 않는다."""
    tag = uuid.uuid4().hex[:8]
    return f'바뀐 소개 {tag}', tag


def _error_color():
    """AppColors.error 의 값 — 앱이 말한 글자 색과 맞대 본다."""
    text = (tools.ROOT / 'frontend' / 'lib' / 'core' / 'theme' / 'app_colors.dart').read_text(encoding='utf-8')
    found = re.search(r'Color error = Color\(0x([0-9A-Fa-f]{8})\)', text)
    if not found:
        raise Blocked('준비: frontend/lib/core/theme/app_colors.dart 에서 AppColors.error 를 못 읽음')
    return int(found.group(1), 16)


def _hex(color):
    return None if color is None else f'0x{color:08X}'


def _vectors(run, account):
    row = _one(run, f"profile_vectors?profile_id=eq.{account['id']}&select=updated_at,self_embedding")
    if not row.get('updated_at'):
        raise Blocked('준비: 벡터 행(profile_vectors)이 없다 — 다시 만들었는지 볼 수 없다')
    return row


def _plant_vectors(run, account):
    """벡터 행의 시각을 하루 전, 문장 벡터를 단위벡터로 심고 읽어 돌려준다 — 이 값이 바뀌었나가 "다시 만들었나" 의 증거다."""
    area2._guard(run, account['id'])
    _vectors(run, account)
    old = _now() - PLANT_AGO
    _patch(run, f"profile_vectors?profile_id=eq.{account['id']}", {'updated_at': old.isoformat(), 'self_embedding': area2._unit(0)})
    row = _vectors(run, account)
    if abs(_at(row['updated_at']) - old) > timedelta(seconds=1) or not row.get('self_embedding'):
        raise Blocked(f'준비: 벡터 행의 시각 · 문장 벡터를 심지 못했다 — 읽은 값 {row.get("updated_at")}')
    return row


def _remade(check, run, account, planted, launched):
    """벡터 행을 다시 만들었다 — 시각이 앱을 켠 시각(−여유) 이후이고(심어 둔 시각은 하루 전이라 안 건드렸다면 그 앞이다) 문장 벡터가 달라졌다."""
    db = _vectors(run, account)
    at = _at(db['updated_at'])
    check.that(at >= launched - SKEW, f"벡터 updated_at {db['updated_at']}(기대 앱을 켠 시각 {launched.isoformat()} − {SKEW.seconds}초 이후)")
    check.that(db['self_embedding'] != planted['self_embedding'], '벡터 self_embedding 이 심어 둔 값 그대로 — 문장 벡터를 다시 만들지 않음')


def _kept(check, run, account, planted):
    """벡터 행이 그대로다(키 · 닉네임만 고치면 다시 만들지 않는다)."""
    db = _vectors(run, account)
    check.that(_at(db['updated_at']) == _at(planted['updated_at']), f"벡터 updated_at {db['updated_at']}(기대 그대로 {planted['updated_at']})")
    check.that(db['self_embedding'] == planted['self_embedding'], '벡터 self_embedding 이 바뀜(기대 그대로)')


def _paid_case(name, body):
    """앱이 저장을 눌러 서버가 임베딩(유료)을 부르는 가설 — E2E_REAL_AI=1 이 아니면 요청을 한 번도 보내지 않고, 앱이 켜진 뒤에는 한 번만 돈다
    (러너가 fail 을 한 번 더 돌려도 같은 비용을 두 번 내지 않고 첫 시도의 이유를 그대로 돌려준다). [body] 는 앱을 켜기 직전에 `paid()` 를 부른다."""
    def case(run, phone):
        real_ai_gate()
        if name in _PAID:
            result, note = _PAID[name]
            if result == 'fail':
                return result, f'{note} — 유료 호출 뒤라 다시 하지 않음'
            raise Blocked(f'이미 한 번 유료 호출 — 재시도 안 함(앞 결과 {result}: {note})')

        def paid():
            _PAID[name] = ('blocked', '앱이 저장을 누른 뒤 결과가 나오기 전에 멈춤')  # 여기부터는 임베딩(유료)이 나갈 수 있다
        try:
            result = body(run, phone, paid)
        except Blocked as e:
            if name in _PAID:
                _PAID[name] = ('blocked', str(e))
            raise
        if name in _PAID:
            _PAID[name] = result
        return result
    return case


# ── E-ME-07 · 18 자기소개 저장 ──────────────────────────────────────────────────────────────────────

def _bio_text(run, account):
    return _profile(run, account, 'bio').get('bio')


def p_me_07(run, phone, paid):
    check = Check()
    account, token = _home(run)
    old = _bio_text(run, account)
    if not old:
        raise Blocked('준비: 처음 자기소개가 비어 있다 — "옛 글이 안 보인다" 가 증거가 못 된다')
    new, tag = _new_bio()
    paid()
    said = _app(check, phone(token_hash=token, bio=f'  {new}  ', tag=tag, old=old))
    got = _bio_text(run, account)
    check.that(got == new, f'DB 자기소개 {got!r}(기대 앞뒤 공백을 뗀 {new!r})')
    check.that(said.get('save_title', MISSING) == TITLES['15-5'], f"저장 뒤 화면 {said.get('save_title', MISSING)!r}(기대 15-5 {TITLES['15-5']!r})")
    check.that(said.get('card_bios', MISSING) == [new], f"15-4 자기소개 {said.get('card_bios', MISSING)}(기대 [{new!r}])")
    check.that(said.get('old_in_card') is False, f"15-4 에 옛 글이 보임 {said.get('old_in_card', MISSING)}(기대 안 보임)")
    return check.result()


def p_me_18(run, phone, paid):
    check = Check()
    account, token = _home(run)
    planted = _plant_vectors(run, account)
    new, tag = _new_bio()
    launched = _now()
    paid()
    said = _app(check, phone(token_hash=token, bio=f'  {new}  ', tag=tag))
    got = _bio_text(run, account)
    check.that(got == new, f'DB 자기소개 {got!r}(기대 앞뒤 공백을 뗀 {new!r})')
    check.that(said.get('title', MISSING) == TITLES['15-5'], f"저장 뒤 화면 {said.get('title', MISSING)!r}(기대 15-5 {TITLES['15-5']!r})")
    check.that(said.get('manage_bios', MISSING) == [new], f"15-5 자기소개 {said.get('manage_bios', MISSING)}(기대 [{new!r}])")
    _remade(check, run, account, planted, launched)
    return check.result(f'벡터 시각은 PC 시계가 아니라 하루 전으로 심어 둔 값과 앱을 켠 시각 − {SKEW.seconds}초 여유로 견줬다')


# ── E-ME-19 · 34 키만 고치기 ─────────────────────────────────────────────────────────────────────────

NEW_HEIGHT = '180'


def _height_saved(check, said, before):
    """키만 바꿔 저장한 앱의 말 — 처음 키 칸 · 저장 버튼 · 저장 뒤 15-5."""
    check.that(said.get('before', MISSING) == before, f"처음 키 칸 {said.get('before', MISSING)!r}(기대 {before!r})")
    check.that(said.get('save_enabled') is True, f"저장 버튼 켜짐 {said.get('save_enabled', MISSING)}(기대 켜짐)")
    check.that(said.get('title', MISSING) == TITLES['15-5'], f"저장 뒤 화면 {said.get('title', MISSING)!r}(기대 15-5 {TITLES['15-5']!r})")


def p_me_19(run, phone):
    check = Check()
    account, token = _home(run)
    _set(run, account, '키 178', height_cm=178)
    planted = _plant_vectors(run, account)
    said = _app(check, phone(token_hash=token, height=NEW_HEIGHT))
    _height_saved(check, said, '178')
    got = _profile(run, account, 'height_cm').get('height_cm')
    check.that(got == int(NEW_HEIGHT), f'DB 키 {got!r}(기대 {NEW_HEIGHT})')
    _kept(check, run, account, planted)
    return check.result('키 저장은 임베딩을 안 부른다(me/router.py:233 bio 일 때만) — 유료 문 없이 돈다')


def p_me_34(run, phone):
    check = Check()
    account, token = _home(run)
    changed = _now() - timedelta(days=40)
    _unlock(run, account, changed)
    _set(run, account, '키 178', height_cm=178)
    before = _profile(run, account, 'nickname').get('nickname')
    said = _app(check, phone(token_hash=token, height=NEW_HEIGHT))
    _height_saved(check, said, '178')
    db = _profile(run, account, 'height_cm,nickname,nickname_changed_at')
    check.that(db.get('height_cm') == int(NEW_HEIGHT), f"DB 키 {db.get('height_cm')!r}(기대 {NEW_HEIGHT})")
    check.that(db.get('nickname') == before, f"DB 닉네임 {db.get('nickname')!r}(기대 그대로 {before!r})")
    at = db.get('nickname_changed_at')
    check.that(at and _at(at) == changed, f'DB nickname_changed_at {at}(기대 심어 둔 {changed.isoformat()} 그대로 — 30일 잠금이 새로 시작되면 안 된다)')
    return check.result()


# ── E-ME-20 · 23 자기소개 칸 ─────────────────────────────────────────────────────────────────────────

def p_me_20(run, phone):
    check = Check()
    account, token = _home(run)
    old = _bio_text(run, account)
    said = _app(check, phone(token_hash=token))
    check.that(said.get('clear_enabled') is False, f"글을 다 비운 뒤 저장 버튼 켜짐 {said.get('clear_enabled', MISSING)}(기대 꺼짐)")
    check.that(said.get('spaces_enabled') is False, f"공백 3칸 뒤 저장 버튼 켜짐 {said.get('spaces_enabled', MISSING)}(기대 꺼짐)")
    check.that(said.get('typed_enabled') is True,
               f"글을 쓰면 저장 버튼 켜짐 {said.get('typed_enabled', MISSING)}(기대 켜짐 — 꺼진 채면 위 두 줄이 증거가 못 된다)")
    check.reply('API PATCH bio="   "', _api(run, 'PATCH', '/me/profile', account['token'], {'bio': '   '}, **area2._ONCE), 422,
                contains='자기소개를 입력해 주세요')
    got = _bio_text(run, account)
    check.that(got == old, f'DB 자기소개 {got!r}(기대 그대로 {old!r})')
    return check.result()


def p_me_23(run, phone):
    check = Check()
    account, token = _home(run)
    old = _bio_text(run, account)
    typed, _ = _new_bio()
    said = _app(check, phone(token_hash=token, typed=typed))
    check.that(said.get('first_field', MISSING) == old, f"처음 연 칸 {said.get('first_field', MISSING)!r}(기대 DB 자기소개 {old!r})")
    check.that(said.get('typed_field', MISSING) == typed, f"고친 글을 칸에 치지 못함 {said.get('typed_field', MISSING)!r}(기대 {typed!r})")
    check.that(said.get('reopened_field', MISSING) == old,
               f"다시 연 칸 {said.get('reopened_field', MISSING)!r}(기대 서버 값 {old!r} — 고치다 만 글은 사라져야 한다)")
    got = _bio_text(run, account)
    check.that(got == old, f'DB 자기소개 {got!r}(기대 그대로 {old!r})')
    return check.result()


# ── E-ME-21 태그 편집 ────────────────────────────────────────────────────────────────────────────────

def p_me_21(run, phone):
    check = Check()
    account, token = _home(run)
    _set(run, account, '관심사 4개', interest_tags=INTERESTS)
    mine = _profile(run, account, 'my_traits,ideal_traits')
    said = _app(check, phone(token_hash=token, extra=EXTRA, sixth=SIXTH))
    five = sorted(INTERESTS + [EXTRA])
    got = lambda key: sorted(said.get(key) or [])
    check.that(got('start') == sorted(INTERESTS), f"처음 고른 칩 {said.get('start', MISSING)}(기대 {sorted(INTERESTS)})")
    check.that(got('five') == five, f"1개 더 고른 뒤 {said.get('five', MISSING)}(기대 5개 {five})")
    check.that(got('after_sixth') == five, f"6번째를 눌렀더니 {said.get('after_sixth', MISSING)}(기대 5개 그대로 {five})")
    two = said.get('two') or []
    check.that(len(two) == 2 and set(two) <= set(five), f'3개를 끈 뒤 {said.get("two", MISSING)}(기대 5개 중 2개)')
    check.that(said.get('two_save_enabled') is False, f"2개만 남긴 뒤 저장 버튼 {said.get('two_save_enabled', MISSING)}(기대 꺼짐)")
    check.that(got('back_to_five') == five, f"다시 5개로 되돌린 뒤 {said.get('back_to_five', MISSING)}(기대 {five})")
    check.that(said.get('title', MISSING) == TITLES['15c'], f"저장 뒤 화면 {said.get('title', MISSING)!r}(기대 15c {TITLES['15c']!r})")
    db = _profile(run, account, 'interest_tags')
    check.that(sorted(db.get('interest_tags') or []) == five, f"DB 관심사 {db.get('interest_tags')}(기대 5개 {five})")
    chips = sorted(five + list(mine.get('my_traits') or []) + list(mine.get('ideal_traits') or []))
    check.that(got('chips') == chips, f"15c 칩 {said.get('chips', MISSING)}(기대 세 섹션 {len(chips)}개 {chips})")
    return check.result()


# ── E-ME-24 · 25 선호 조건 ───────────────────────────────────────────────────────────────────────────

def _prefs_ready(run, account):
    """처음 값(나이 22~27 · 키 165~180 · 얼굴상 2 · 인상 1) + 벡터 행."""
    _set(run, account, '선호 조건', **IDEAL_PREFS)
    return _plant_vectors(run, account)


def _prefs_kept(check, run, account, *skip):
    """나이 · 키를 뺀 선호 조건(얼굴상 · 인상)이 처음 그대로다. [skip] 에 든 이름('나이' · '키')은 보지 않는다."""
    db = _profile(run, account, PREFS)
    if '키' not in skip:
        check.that((db.get('preferred_height_min'), db.get('preferred_height_max')) == (165, 180),
                   f"DB 키 {db.get('preferred_height_min')}~{db.get('preferred_height_max')}(기대 165~180 그대로)")
    check.that(sorted(db.get('preferred_animal_types') or []) == ['cat', 'dog'], f"DB 얼굴상 {db.get('preferred_animal_types')}(기대 ['dog', 'cat'] 그대로)")
    check.that(db.get('preferred_impression_types') == ['kind'], f"DB 인상 {db.get('preferred_impression_types')}(기대 ['kind'] 그대로)")
    return db


def p_me_24(run, phone, paid):
    check = Check()
    account, token = _home(run)
    planted = _prefs_ready(run, account)
    launched = _now()
    paid()
    said = _app(check, phone(token_hash=token))
    for key, want, label in (('title', TITLES['06-1'], '앱바'), ('first_age', '22세 ~ 27세', '처음 나이 줄'), ('first_height', '165cm ~ 180cm', '처음 키 줄'),
                             ('changed_age', '24세 ~ 30세', '슬라이더로 고른 나이 줄'), ('back_title', TITLES['15-5'], '저장 뒤 화면(15-5)'),
                             ('ideal_note', '나이 24–30세 · 키 165–180cm', '15-5 이상형 줄')):
        check.that(said.get(key, MISSING) == want, f'{label} {said.get(key, MISSING)!r}(기대 {want!r})')
    db = _prefs_kept(check, run, account)
    check.that((db.get('preferred_age_min'), db.get('preferred_age_max')) == (24, 30),
               f"DB 나이 {db.get('preferred_age_min')}~{db.get('preferred_age_max')}(기대 24~30)")
    _remade(check, run, account, planted, launched)
    return check.result('슬라이더는 끌지 않고 onChanged 를 불렀다 — 끌기는 사람이 본다')


def p_me_25(run, phone, paid):
    check = Check()
    account, token = _home(run)
    planted = _prefs_ready(run, account)
    launched = _now()
    paid()
    said = _app(check, phone(token_hash=token))
    check.that(said.get('age_ignored') is True, f"나이 체크 {said.get('age_ignored', MISSING)}(기대 켜짐)")
    check.that(said.get('height_ignored') is True, f"키 체크 {said.get('height_ignored', MISSING)}(기대 켜짐)")
    check.that(said.get('back_title', MISSING) == TITLES['15-5'], f"저장 뒤 화면 {said.get('back_title', MISSING)!r}(기대 15-5 {TITLES['15-5']!r})")
    check.that(said.get('ideal_note', MISSING) == '나이 · 키 모두 상관없어요',
               f"15-5 이상형 줄 {said.get('ideal_note', MISSING)!r}(기대 '나이 · 키 모두 상관없어요')")
    db = _prefs_kept(check, run, account, '키')
    check.that((db.get('preferred_age_min'), db.get('preferred_age_max')) == (19, 35),
               f"DB 나이 {db.get('preferred_age_min')}~{db.get('preferred_age_max')}(기대 19~35)")
    check.that((db.get('preferred_height_min'), db.get('preferred_height_max')) == (None, None),
               f"DB 키 {db.get('preferred_height_min')}~{db.get('preferred_height_max')}(기대 비어 있음)")
    _remade(check, run, account, planted, launched)
    return check.result()


# ── E-ME-26 얼굴상 · 인상 개수 ───────────────────────────────────────────────────────────────────────

def _appearance(check, said, kind, prefix, start, three):
    """한 종류(얼굴상 또는 인상)의 앱의 말 — 처음 · 끄고 · 0개일 때 저장 · 3개 · 4번째."""
    check.that(sorted(said.get(f'{prefix}_start') or []) == start, f"{kind} 처음 {said.get(f'{prefix}_start', MISSING)}(기대 {start})")
    check.that(said.get(f'{prefix}_zero') == [], f"{kind} 끄고 난 뒤 {said.get(f'{prefix}_zero', MISSING)}(기대 [])")
    check.that(said.get(f'{prefix}_zero_save') is False, f"{kind} 0개일 때 저장 버튼 {said.get(f'{prefix}_zero_save', MISSING)}(기대 꺼짐)")
    check.that(sorted(said.get(f'{prefix}_three') or []) == three, f"{kind} 3개를 고른 뒤 {said.get(f'{prefix}_three', MISSING)}(기대 {three})")
    check.that(sorted(said.get(f'{prefix}_four') or []) == three, f"{kind} 4번째를 눌렀더니 {said.get(f'{prefix}_four', MISSING)}(기대 3개 그대로 {three})")


def p_me_26(run, phone):
    check = Check()
    account, token = _home(run)
    _set(run, account, '얼굴상 1개 · 인상 1개', preferred_animal_types=['dog'], preferred_impression_types=['kind'])
    said = _app(check, phone(token_hash=token))
    _appearance(check, said, '얼굴상', 'animal', ['dog'], ['bear', 'cat', 'fox'])
    _appearance(check, said, '인상', 'impression', ['kind'], ['arab', 'chic', 'tofu'])
    check.that(said.get('three_save') is True, f"얼굴상 · 인상 3개씩일 때 저장 버튼 {said.get('three_save', MISSING)}(기대 켜짐)")
    body = {'preferred_age_min': 20, 'preferred_age_max': 30, 'preferred_animal_types': ['dog'], 'preferred_impression_types': ['kind']}
    for label, key, four in (('API 얼굴상 4개', 'preferred_animal_types', ['dog', 'cat', 'fox', 'bear']),
                             ('API 인상 4개', 'preferred_impression_types', ['arab', 'tofu', 'kind', 'chic'])):
        reply = _api(run, 'POST', '/profile-onboarding/ideal-conditions', account['token'], {**body, key: four}, **area2._ONCE)
        check.reply(label, reply, 422, contains=AT_MOST_3)
    db = _profile(run, account, 'preferred_animal_types,preferred_impression_types')
    check.that((db.get('preferred_animal_types'), db.get('preferred_impression_types')) == (['dog'], ['kind']),
               f"DB 얼굴상 {db.get('preferred_animal_types')} · 인상 {db.get('preferred_impression_types')}(기대 저장 안 함 ['dog'] · ['kind'])")
    return check.result()


# ── E-ME-27 · 31 · 33 · 36 닉네임 ────────────────────────────────────────────────────────────────────

def p_me_27(run, phone):
    check = Check()
    account, token = _home(run)
    _unlock(run, account)
    nickname = _free_nickname(run)
    launched = _now()
    said = _app(check, phone(token_hash=token, nickname=nickname))
    check.that(said.get('ok') is True, f"'사용할 수 있는 닉네임이에요' {said.get('ok', MISSING)}(기대 보임)")
    check.that(said.get('save_enabled') is True, f"저장 버튼 {said.get('save_enabled', MISSING)}(기대 켜짐)")
    check.that(said.get('title', MISSING) == TITLES['15-5'], f"저장 뒤 화면 {said.get('title', MISSING)!r}(기대 15-5 {TITLES['15-5']!r})")
    check.that(said.get('toast_seen') is True, f"토스트 '저장했어요' {said.get('toast_seen', MISSING)}(기대 보임)")
    ms = said.get('toast_ms')
    check.that(isinstance(ms, int) and TOAST_MS[0] <= ms <= TOAST_MS[1], f'토스트가 떠 있던 시간 {ms}ms(기대 {TOAST_MS[0]}~{TOAST_MS[1]}ms — 약 2초)')
    db = _profile(run, account, 'nickname,nickname_changed_at')
    check.that(db.get('nickname') == nickname, f"DB 닉네임 {db.get('nickname')!r}(기대 {nickname!r})")
    at = db.get('nickname_changed_at')
    check.that(at and launched - SKEW <= _at(at) <= _now() + SKEW, f'DB nickname_changed_at {at}(기대 저장 시각 — {SKEW.seconds}초 여유 안)')
    return check.result(f'저장 시각은 앱을 켠 때 − {SKEW.seconds}초 ~ 지금 + {SKEW.seconds}초 안이면 통과(시나리오 ±1분 + PC · DB 시계 차이 여유)')


def p_me_31(run, phone):
    check = Check()
    account, token = _home(run)
    _unlock(run, account)
    original = _profile(run, account, 'nickname').get('nickname')
    nickname = _free_nickname(run)
    locked = []

    def lock(said):
        """앱이 15-6 을 연 채 멈춘 사이 — 다른 곳에서 바꾼 것처럼 잠금을 지금으로."""
        at = _now()
        _write(run, account, {'nickname_changed_at': at.isoformat()})
        locked.append(at)
    said = _app(check, phone(token_hash=token, nickname=nickname, midway=lock))
    check.that(said.get('enabled_at_open') is True, f"15-6 을 열었을 때 닉네임 칸 켜짐 {said.get('enabled_at_open', MISSING)}(기대 켜짐 — 잠금은 연 뒤에 걸린다)")
    check.that(said.get('ok_before') is True, f"저장 전 '사용할 수 있는 닉네임이에요' {said.get('ok_before', MISSING)}(기대 보임)")
    check.that(said.get('error') is True, f"닉네임 칸 아래 '닉네임은 30일에 한 번 바꿀 수 있어요' {said.get('error', MISSING)}(기대 보임)")
    check.that(said.get('error_icon') is True, f"오류 줄의 경고 아이콘 {said.get('error_icon', MISSING)}(기대 있음)")
    want = _error_color()
    check.that(said.get('error_color') == want, f"오류 글자 색 {_hex(said.get('error_color'))}(기대 빨간 {_hex(want)})")
    check.that(said.get('on_edit') is True, f"저장이 막힌 뒤 15-6 이 열려 있어야 한다(머물러야 함): {said.get('on_edit', MISSING)}")
    check.that(said.get('title', MISSING) == TITLES['15-6'], f"저장이 막힌 뒤 앱바 {said.get('title', MISSING)!r}(15-6 {TITLES['15-6']!r} 에 머물러야 한다)")
    db = _profile(run, account, 'nickname,nickname_changed_at')
    check.that(db.get('nickname') == original, f"DB 닉네임 {db.get('nickname')!r}(기대 그대로 {original!r})")
    at = db.get('nickname_changed_at')
    check.that(bool(locked) and at is not None and _at(at) == locked[0], f'DB nickname_changed_at {at}(기대 PC 가 건 {locked[0].isoformat() if locked else None} 그대로)')
    return check.result()


def p_me_33(run, phone):
    check = Check()
    account, token = _home(run)
    _unlock(run, account)
    for name in FREE_NAMES:
        if _rows(run, f'profiles?nickname=ilike.{quote(name)}&select=id'):
            raise Blocked(f'준비: 닉네임 {name!r} 가 이미 쓰이고 있어 "통과" 를 볼 수 없다')
    said = _app(check, phone(token_hash=token, typed=PROBES))
    probes = {p.get('typed'): p for p in said.get('probes') or []}
    cut = []
    for typed in PROBES:
        probe = probes.get(typed)
        if probe is None:
            check.that(False, f'닉네임 {typed!r}: 앱이 말하지 않음')
            continue
        cleaned = FILTERED.sub('', typed)
        field = probe.get('field')
        check.that(field in (typed, cleaned), f'닉네임 {typed!r}: 칸에 든 글자 {field!r}(기대 {typed!r} 또는 걸러진 {cleaned!r})')
        if field != typed:
            cut.append(f'{typed!r} → {field!r}')
        if isinstance(field, str) and NICKNAME.fullmatch(field):
            check.that(probe.get('ok') is True, f"닉네임 {typed!r}(칸 {field!r}): '사용할 수 있는 닉네임이에요' {probe.get('ok')}(기대 보임)")
            check.that(probe.get('bad') is False, f"닉네임 {typed!r}(칸 {field!r}): 형식 오류 문구 {probe.get('bad')}(기대 없음)")
            check.that(probe.get('taken') is False, f"닉네임 {typed!r}(칸 {field!r}): '이미 있는 닉네임이에요' {probe.get('taken')}(기대 없음)")
            check.that(probe.get('save_enabled') is True, f"닉네임 {typed!r}(칸 {field!r}): 저장 버튼 {probe.get('save_enabled')}(기대 켜짐)")
        else:
            check.that(probe.get('bad') is True, f"닉네임 {typed!r}(칸 {field!r}): '한글 또는 영문 2~5자로 입력해 주세요' {probe.get('bad')}(기대 보임)")
            check.that(probe.get('ok') is False, f"닉네임 {typed!r}(칸 {field!r}): '사용할 수 있는 닉네임이에요' {probe.get('ok')}(기대 없음)")
            check.that(probe.get('save_enabled') is False, f"닉네임 {typed!r}(칸 {field!r}): 저장 버튼 {probe.get('save_enabled')}(기대 꺼짐)")
    return check.result('입력칸이 숫자 · 기호를 걸러 낸다(' + ', '.join(cut) + ') — 시나리오는 오류 문구를 기대했지만 그 글자는 칸에 들어가지 않는다' if cut else '')


def p_me_36(run, phone):
    check = Check()
    account, token = _home(run)
    _unlock(run, account)
    other = _free_nickname(run)
    before = _profile(run, account, 'height_cm,nickname')
    said = _app(check, phone(token_hash=token, other=other))
    for key, want, label in (('untouched_enabled', False, '아무것도 안 바꾼 채 저장 버튼'), ('height_changed_enabled', True, '키를 바꾸면 저장 버튼'),
                             ('height_back_enabled', False, '키를 되돌리면 저장 버튼'), ('nick_changed_enabled', True, '닉네임을 바꾸면 저장 버튼'),
                             ('nick_back_enabled', False, '닉네임을 되돌리면 저장 버튼')):
        check.that(said.get(key) is want, f"{label} {'켜짐' if said.get(key) else '꺼짐' if key in said else MISSING}(기대 {'켜짐' if want else '꺼짐'})")
    check.that(said.get('height', MISSING) == str(before['height_cm']), f"원래 키 {said.get('height', MISSING)!r}(기대 DB 키 {before['height_cm']})")
    check.that(said.get('nickname', MISSING) == before['nickname'], f"원래 닉네임 {said.get('nickname', MISSING)!r}(기대 DB 닉네임 {before['nickname']!r})")
    after = _profile(run, account, 'height_cm,nickname')
    check.that(after == before, f'DB 키 · 닉네임 {after}(기대 저장 안 함 {before})')
    return check.result()


def _cut_settled(phone):
    """비행기 모드를 켜고 CUT_SETTLE 초 쉰다 — 앱이 다음 멈춤 뒤 곧바로 치기 때문에, 쉬지 않으면 망이 살아 있는 채 확인 요청이 나간다."""
    cut = _cut(phone)

    def settled(said):
        cut(said)
        time.sleep(CUT_SETTLE)
    return settled


def p_edge_02(run, phone):
    """E-EDGE-02 — 닉네임 중복 확인 중 망이 끊겨도 문구 0개 · 저장 버튼 켜짐 · 저장은 서버 판정."""
    check = Check()
    account, token = _home(run)
    _unlock(run, account)
    nickname = _free_nickname(run)
    launched = _now()
    said = offline(phone, check, _cut_settled(phone), _restore(phone), token_hash=token, nickname=nickname)
    shown = [label for key, label in (('off_ok', '사용할 수 있는'), ('off_bad', '형식 오류'), ('off_taken', '이미 있는')) if said.get(key) is True]
    check.that(not shown, f"끊긴 중복 확인 문구 {shown}(기대 0개)")
    # 대조군 — 문구 0개 · 버튼 켜짐은 앱이 '확인 중…' 인 채여도(망이 살아 있고 응답만 느릴 때) 참이다. 끊겼다면 확인이 실패해 '확인 중…' 이 사라진다.
    check.that(said.get('off_checking') is False, f"끊긴 뒤 '확인 중…' 이 {said.get('off_checking', MISSING)}(기대 사라짐 False — 남아 있으면 망이 끊겼다는 증거가 아니다)")
    check.that(said.get('off_field', MISSING) == nickname, f"끊긴 뒤 닉네임 칸 {said.get('off_field', MISSING)!r}(기대 {nickname!r})")
    check.that(said.get('off_save_enabled') is True, f"끊긴 뒤 저장 버튼 {said.get('off_save_enabled', MISSING)}(기대 켜짐)")
    check.that(said.get('save_enabled') is True, f"복구 뒤 저장 버튼 {said.get('save_enabled', MISSING)}(기대 켜짐)")
    check.that(said.get('title', MISSING) == TITLES['15-5'], f"저장 뒤 화면 {said.get('title', MISSING)!r}(기대 15-5 {TITLES['15-5']!r})")
    db = _profile(run, account, 'nickname,nickname_changed_at')
    check.that(db.get('nickname') == nickname, f"DB 닉네임 {db.get('nickname')!r}(기대 {nickname!r})")
    at = db.get('nickname_changed_at')
    check.that(at and launched - SKEW <= _at(at) <= _now() + SKEW, f'DB nickname_changed_at {at}(기대 저장 시각 — {SKEW.seconds}초 여유 안)')
    return check.result()


# ── E-ME-35 키 범위 ──────────────────────────────────────────────────────────────────────────────────

def p_me_35(run, phone):
    check = Check()
    account, token = _home(run)
    _set(run, account, '키 178', height_cm=178)
    said = _app(check, phone(token_hash=token, bad=BAD_HEIGHTS, good=GOOD_HEIGHTS))
    lines = {line.get('typed'): line for line in said.get('rows') or []}
    for typed in BAD_HEIGHTS:
        line = lines.get(typed, {})
        check.that(line.get('error') is True, f"키 {typed!r}: '숫자 3자리를 확인해 주세요' {line.get('error', MISSING)}(기대 보임)")
        check.that(line.get('save_enabled') is False, f"키 {typed!r}: 저장 버튼 {line.get('save_enabled', MISSING)}(기대 꺼짐)")
    for typed in GOOD_HEIGHTS:
        line = lines.get(typed, {})
        check.that(line.get('error') is False, f"키 {typed!r}: '숫자 3자리를 확인해 주세요' {line.get('error', MISSING)}(기대 없음)")
        check.that(line.get('save_enabled') is True, f"키 {typed!r}: 저장 버튼 {line.get('save_enabled', MISSING)}(기대 켜짐)")
        check.that(line.get('title', MISSING) == TITLES['15-5'], f"키 {typed!r}: 저장 뒤 화면 {line.get('title', MISSING)!r}(기대 15-5 {TITLES['15-5']!r})")
        check.that(line.get('reopened', MISSING) == typed, f"키 {typed!r}: 저장 뒤 15-6 을 다시 연 칸 {line.get('reopened', MISSING)!r}(기대 {typed!r})")
    last = int(GOOD_HEIGHTS[-1])
    check.reply('API PATCH 키 300', _api(run, 'PATCH', '/me/profile', account['token'], {'height_cm': 300}, **area2._ONCE), 422, detail=INVALID)
    got = _profile(run, account, 'height_cm').get('height_cm')
    check.that(got == last, f'DB 키 {got!r}(기대 마지막 저장 {last} 그대로 — 300 은 거절돼야 한다)')
    return check.result()


PHONE = {
    'E-ME-07': _paid_case('E-ME-07', p_me_07), 'E-ME-18': _paid_case('E-ME-18', p_me_18), 'E-ME-19': p_me_19, 'E-ME-20': p_me_20,
    'E-ME-21': p_me_21, 'E-ME-23': p_me_23, 'E-ME-24': _paid_case('E-ME-24', p_me_24), 'E-ME-25': _paid_case('E-ME-25', p_me_25),
    'E-ME-26': p_me_26, 'E-ME-27': p_me_27, 'E-ME-31': p_me_31, 'E-ME-33': p_me_33, 'E-ME-34': p_me_34, 'E-ME-35': p_me_35,
    'E-ME-36': p_me_36,
    'E-EDGE-02': p_edge_02,
}

area1.PHONE.update(PHONE)
area1.BUNDLES['area5-act'] = list(PHONE)
tools.CASE_LIMITS.update({'E-ME-33': 600, 'E-ME-35': 600})  # 닉네임 여섯 번 치기 · 키 두 번 저장 + 다시 열기
