"""영역 5 폰 A 한 대 — 나 탭 · 탈퇴 · 경계 중 앱이 화면을 열어 읽거나 누르는 16개(묶음 area5-read).
기대값은 바탕화면 E2E_시나리오_조각/5_나탭_탈퇴_경계.md 의 그 줄(ME 는 5-1 표 · WD 는 5-2 표 · EDGE 는 5-4 표)을 지금 코드와 대조한 것이다.
앱 쪽은 frontend/integration_test/area5_read.dart 의 같은 번호(area5.dart 가 묶는다). 나머지 영역 5 가설은 이 묶음이 아니다.

가설 하나 = 함수 하나 `(run, phone) -> (결과, 메모)`. PC 가 홈 계정을 만들고 서비스 키 DB 로 준비하면, 앱이 화면을 열어 본 것을 Map 으로 말하고
(문구는 사람이 읽는 글자 그대로, 못 본 것은 None — 이 쪽은 `MISSING` 과 가른다), 판정은 여기서 한다. 계정은 가설마다(판이 둘이면 판마다) 새로 만든다.
쓰기는 이번 실행이 만든 계정에만 한다(`area2._guard`). 탈퇴를 실제로 누르는 가설은 이 묶음에 없다 — "정말 영구 삭제" 는 앱 쪽도 누르지 않는다.
나 탭 입구 줄은 InkWell 이 행 전체(Container 안쪽 여백까지, profile_entry_row.dart:31-44)를 감싸지만, 앱은 줄 가운데가 아니라 안의 제목 글자를 누른다.

시나리오와 다르게 도는 것(보고의 "확인 필요"):
  E-ME-01 · 02  시나리오는 "히어로에 하트 잔액" 인데 지금 히어로(profile_hero.dart)에는 하트 숫자가 없다 — 잔액은 15b 시트 본문
                "지금 보유한 하트는 N개예요" 에만 보인다(avatar_regen_sheet.dart:62-69, 결제 개편 전이라 하트 블록은 뺐다). 앱이 "다시 만들기 · 10" 알약을 눌러
                시트를 열고 그 줄을 읽은 뒤 "취소" 로 닫는다(만들기 · 충전 버튼은 안 누른다 — "10 쓰고 만들기" 는 유료 AI). 시트가 그 줄을 보이려면 ready 아바타가
                2장 이상이어야 한다(1장이면 무료 시트, avatar_regen_cost) — 그래서 02 도 아바타를 한 장 더 넣는다.
                나이는 서버 계산식(me/router.py:63 올해 − 출생연도 + 1, 올해는 한국 시각)으로 PC 가 지금 시계로 만든다 — 시나리오의 2026 · 2003 은 쓰지 않는다.
                하트는 처음 있던 잔액에 37 을 더하고 DB 값을 읽어 기대로 쓴다(시나리오의 37 이 아니다). 화면 아바타는 created_at 이 늦은 ready 행(me/router.py:33-37) —
                더한 장(마지막에 넣은 행)을 이틀 앞으로 돌려 "마지막 행" 을 그리는 앱이 걸리게 했다. 앱은 주소 전체(계정 번호가 든다)가 아니라 파일 이름만 말한다.
  E-ME-06       "실사진 4장" 이 아니라 계정 공장의 2장 이상. 응답에서 찾는 값(카톡 아이디 · 실명 · 전화)은 가설이 정해 넣는다 — 다른 칸과 겹치지 않게 고유하게.
                계정 공장은 학번과 카톡 아이디를 같은 `e2e{n}` 으로 넣고(tools.py:587 · 591) 응답은 학번을 싣는다(cards/router.py:363)라서, 공장 값을 그대로 찾으면
                "카톡 아이디가 샜다" 는 거짓 FAIL 이 난다. 응답은 칸 이름(kakao · phone · real_name · photo)과 값(카톡 아이디 · 실명 · 전화 두 모양)과
                실사진 주소(profile-photos 버킷)를 모두 본다.
  E-ME-08       "사진 3장" 은 계정 공장의 2장에 DB 로 한 장을 더한다(Vision · AI 안 부름, 파일은 profile-photos 버킷 `{id}/` 아래라 뒷정리가 지운다).
                섹션 순서는 화면 위치(스크롤을 감안한 y)로 읽는다.
  E-ME-09       판이 둘(끝값 · 전 구간)이라 계정 둘 · 앱 두 번. 나이 문구의 줄표는 en dash(–, profile_manage_screen.dart `_ageRangeNote`).
  E-ME-28 · 29 · 30  PC 가 nickname_changed_at 을 지금 기준 상대값으로 넣고(시나리오의 2026-09-15 는 안 쓴다), 먼저 서버 GET /me/profile 의 풀리는 때가 그 값 + 30일인지 본다
                (서버 시계와 어긋나면 앱 탓으로 세지 않고 blocked). 29 의 두 경계는 판이 둘(계정 둘 · 앱 두 번)이고, 잠긴 쪽은 2분 여유라 앱이 읽는 사이 잠금이
                풀렸을 수 있으면(지난 뒤에 보면) 판정 못 함 = blocked. 30 은 "풀리는 순간 = 오늘 + 20일 16:00 UTC(한국 다음 날 01:00)" 로 골라 UTC 날짜와 한국 날짜가 하루 다르다.
  E-WD-17       시나리오 전제가 낡았다 — 정지 안내 화면에는 로그아웃 AppButton 1개 외에 글자 버튼 "탈퇴하기"(A5, account_suspended_screen.dart:38-51)가 있고 누르면
                14f-1 시트 "정지 중에 탈퇴할까요?" 가 뜬다. 서버 주석(account/router.py:19 "정지 · 미인증인 사람도 나갈 수 있어야 한다")과 앱이 이제 맞는다.
                "정지 계정이 다른 화면으로 못 가는 것"(auth_redirect.dart:40-41 — 지시서의 35-37 은 옛 줄)은 E-SAFE-50 의 stays 가 이미 보니 새로 판정하지 않는다. "정말 영구 삭제" 는 누르지 않는다.
  E-EDGE-13     15-5 · 15-4 는 고칠 값이 없어 열기만 한다(시나리오는 "각각 값을 고친 상태"). 나머지 다섯은 앱이 값을 하나 고친 채(저장 안 함) 멈추고, PC 가 시스템 뒤로를
                보낸 뒤 앱이 도착 화면의 앱바 제목을 말한다.
  E-EDGE-14     15b · 16c 1차 · 16c 최종, 세 번 멈춘다. "아무 요청도 안 간다" 는 DB(아바타 행 · status · 재가입 제한)가 그대로인 것으로 본다.
  E-EDGE-16     동의 전 계정(`new`)으로 02-c 에 닿은 앱에 뒤로를 보낸 뒤 맨 앞 화면이 우리 앱인지(dumpsys) 본다.
  E-EDGE-23     결과 기록 — 뒤로 한 번 뒤 15 면 1겹, 15-5 가 또 나오면 2겹. 두 번째 누름이 15-5 가 아닌 화면에 떨어졌으면 판정 못 함(blocked).
"""

import json
import re
import time
import uuid
from datetime import datetime, timedelta, timezone

from e2e import area1, area2, tools
from e2e.area1 import SEOUL, Check, _api, _app, _at, _one, _patch, _rows, _signed_in
from e2e.area2_phone3 import _add_avatar, _balance, _give
from e2e.area3_phone import MISSING
from e2e.area3_safe import _suspend
from e2e.area4 import stepper
from e2e.tools import Blocked

HEARTS = 37  # 시나리오 ME-01 — 처음 있던 잔액에 더한다
MAJOR = '디자인학과'
REAL_NAME = 'E2E실명확인'  # 가짜 이름 — 응답에 이 글자가 있으면 샌 것
NICKNAME_INTERVAL = timedelta(days=30)  # me/schemas.py NICKNAME_CHANGE_INTERVAL
BACK = ('shell', 'input', 'keyevent', 'KEYCODE_BACK')
TITLES = {'15': '내 프로필', '15-4': '남이 보는 내 프로필', '15-5': '프로필 편집', '15c': '자기소개·태그 수정',  # 앱바 글자(각 화면 코드)
          '06-1': '이상형 조건 수정', 'tag': '관심사 수정', '15-6': '기본 정보 수정', '15-7': '사진 수정', '16': '설정'}
SECTIONS = ['실제 사진', '기본 정보', '선호 조건', '자기소개']  # profile_manage_screen.dart 섹션 제목 순서
DELETED = ['프로필과 인증 정보', '수락 매칭 기록', '모든 대화 내용']  # withdraw_sheets.dart `_DeletedItems`
EN_DASH = '–'
# 선호 조건 두 판 — (이름, 넣을 칸, 나이 줄, 키 줄). 끝값 35 · 150 · 190 은 "이상" · "이하" 가 붙고, 전 구간은 "상관없어요".
PREFERENCES = (
    ('끝값', {'preferred_age_min': 22, 'preferred_age_max': 35, 'preferred_height_min': 150, 'preferred_height_max': 190},
     f'22세{EN_DASH}35세 이상', '150cm 이하 ~ 190cm 이상'),
    ('전 구간', {'preferred_age_min': 19, 'preferred_age_max': 35, 'preferred_height_min': None, 'preferred_height_max': None},
     '상관없어요', '상관없어요'),
)
LEAKY_KEY = re.compile(r'kakao|phone|real_name|photo', re.I)
# EDGE-13 — (앱이 멈추는 이름, 연 화면, 뒤로 뒤 도착 화면, 라벨). 15-5 · 15-4 는 고칠 값이 없다.
EDGE_13 = (('15-5', '15-5', '15', '15-5'), ('15-4', '15-4', '15', '15-4'), ('15c', '15c', '15-5', '15c'),
           ('06-1', '06-1', '15-5', '06-1 편집'), ('tag', 'tag', '15c', '태그 편집(관심사)'), ('15-6', '15-6', '15-5', '15-6'),
           ('15-7', '15-7', '15-5', '15-7'))
NO_VALUE_TO_EDIT = {'15-5', '15-4'}
# EDGE-14 — (멈추는 이름, 뒤로 뒤 도착 화면, 라벨, 다른 시트가 열렸는지 보는 칸)
EDGE_14 = (('regen', '15', '15b', None), ('withdraw-first', '16', '16c 1차', 'final_open'), ('withdraw-final', '16', '16c 최종', 'first_open'))
SAVED = ('nickname,nickname_changed_at,bio,height_cm,mbti,major,interest_tags,my_traits,ideal_traits,preferred_age_min,preferred_age_max,'
         'preferred_height_min,preferred_height_max,preferred_mbti_flags,preferred_animal_types,preferred_impression_types,status')


def _now():
    """지금(UTC) — 시험이 시계를 쥘 수 있게 한 곳으로 모았다."""
    return datetime.now(timezone.utc)


# ── 준비 · 읽기 ──────────────────────────────────────────────────────────────────────────────────────

def _home(run, **basic):
    """홈 계정과 앱이 로그인할 1회용 토큰. 쓰기는 이번 실행이 만든 계정에만(가드)."""
    account = run.account('home', **basic)
    area2._guard(run, account['id'])
    return account, run.link(account['email'])


def _file(row):
    return row['storage_path'].rsplit('/', 1)[-1]


def _ready_avatars(run, account):
    rows = _rows(run, f"profile_avatars?profile_id=eq.{account['id']}&select=id,storage_path,created_at,status")
    return [r for r in rows if r['status'] == 'ready']


def _two_avatars(run, account):
    """ready 아바타 2장 — 더한 장(마지막에 넣은 행)의 created_at 을 이틀 앞으로 돌린다. 화면 아바타는 created_at 이 늦은 쪽이라
    "마지막 행" 을 그리는 앱은 오래된 그림을 그린다. 화면이 그려야 할 파일 이름을 돌려준다."""
    before = {r['id'] for r in _ready_avatars(run, account)}
    _add_avatar(run, account)
    rows = _ready_avatars(run, account)
    added = [r for r in rows if r['id'] not in before]
    if len(rows) != 2 or len(added) != 1:
        raise Blocked(f'준비: ready 아바타 {len(rows)}장(새로 더한 {len(added)}장) — 기대 2장')
    _patch(run, f"profile_avatars?id=eq.{added[0]['id']}", {'created_at': (_now() - timedelta(days=2)).isoformat()})
    newest = max(_ready_avatars(run, account), key=lambda r: _at(r['created_at']))
    if newest['id'] == added[0]['id']:
        raise Blocked('준비: created_at 을 돌렸는데 더한 장이 아직 가장 늦다')
    return _file(newest)


def _hearts_line(check, said, balance):
    """15b 시트의 보유 하트 줄과 "취소" 뒤 시트 닫힘 — 01 · 02 가 같이 본다."""
    text = said.get('heart_text')
    check.that(f'지금 보유한 하트는 {balance}개예요' in (text or ''), f'15b 시트의 보유 하트 줄 {text!r}(기대 "지금 보유한 하트는 {balance}개예요")')
    check.that(said.get('sheet_closed') is True, f"취소 뒤 시트 닫힘 {said.get('sheet_closed', MISSING)}(기대 True)")


def _signup_blocks(run):
    """재가입 제한 행(전체) — 탈퇴를 안 눌렀으면 앞뒤가 같다. 이 표는 id 칸이 없어 email_hmac 으로 읽고, 순서를 정해 읽는다 —
    행이 천 개를 넘으면 PostgREST 가 잘라 돌려주는데 순서가 없으면 앞 · 뒤가 서로 다른 쪽을 읽어 거짓 FAIL 이 난다."""
    return sorted(r['email_hmac'] for r in _rows(run, 'signup_blocks?select=email_hmac&order=email_hmac'))


def _unchanged(run, account, check, blocks, label, status='active'):
    """탈퇴하지 않았다 — status 그대로 · withdrawn_at 비어 있음 · 재가입 제한 행 그대로."""
    row = _one(run, f"profiles?id=eq.{account['id']}&select=status,withdrawn_at")
    check.that(row.get('status') == status, f"{label} 뒤 status {row.get('status')!r}(기대 {status})")
    check.that(row.get('withdrawn_at') is None, f"{label} 뒤 withdrawn_at {row.get('withdrawn_at')!r}(기대 비어 있음)")
    check.that(_signup_blocks(run) == blocks, f'{label} 뒤 signup_blocks 가 바뀜')


def _avatar_rows(run, account):
    rows = _rows(run, f"profile_avatars?profile_id=eq.{account['id']}&select=id,status,storage_path")
    return sorted((r.get('id'), r.get('status'), r.get('storage_path')) for r in rows)


def _saved(run, account):
    """저장될 수 있는 것 전부 — 프로필 칸 · 사진 행 · 아바타 행. 뒤로 나간 뒤에도 같아야 한다."""
    me = account['id']
    photos = _rows(run, f'profile_photos?profile_id=eq.{me}&select=id,position,is_avatar_source,storage_path')
    return {'profile': _one(run, f'profiles?id=eq.{me}&select={SAVED}'),
            'photos': sorted((p.get('id'), p.get('position'), p.get('is_avatar_source'), p.get('storage_path')) for p in photos),
            'avatars': _avatar_rows(run, account)}


def _press_back(phone, pressed):
    """앱이 `step` 에서 멈춘 사이 시스템 뒤로(KEYCODE_BACK)를 보낸다 — 앱이 말한 멈춘 이름을 [pressed] 에 적는다."""
    def press(said):
        pressed.append(said.get('step'))
        tools.adb(phone.serial, *BACK)
    return press


# ── E-ME-01 · 02 ────────────────────────────────────────────────────────────────────────────────────

def p_me_01(run, phone):
    check = Check()
    account, token = _home(run)
    me = account['id']
    _patch(run, f'profiles?id=eq.{me}', {'birth_year': datetime.now(SEOUL).year - 23, 'major': MAJOR})
    newest = _two_avatars(run, account)
    _give(run, account, HEARTS)
    balance = _balance(run, account)
    profile = _one(run, f'profiles?id=eq.{me}&select=nickname,birth_year,major,universities(name)')
    if not balance or not profile.get('nickname') or not profile.get('universities'):
        raise Blocked(f"준비: 하트 {balance} · 닉네임 {profile.get('nickname')!r} · 학교 {profile.get('universities')!r} — 읽은 값이 비어 있다")
    said = _app(check, phone(token_hash=token))
    age = datetime.now(SEOUL).year - profile['birth_year'] + 1  # me/router.py:63
    want = f"{profile['nickname']}, {age}"
    check.that(said.get('name_line', MISSING) == want, f"이름 줄 {said.get('name_line', MISSING)!r}(기대 {want!r})")
    school = f"{profile['universities']['name']}\n{profile['major']}"
    check.that(said.get('school', MISSING) == school, f"학교 줄 {said.get('school', MISSING)!r}(기대 {school!r})")
    check.that(said.get('avatar_file', MISSING) == newest,
               f"아바타 파일 {said.get('avatar_file', MISSING)!r}(기대 created_at 이 늦은 ready 행의 {newest!r})")
    for key, label in (('badge', '"학생 인증" 배지'), ('chip', '"상대에게 이렇게 보여요" 칩')):
        check.that(said.get(key) is True, f'{label} {said.get(key, MISSING)}(기대 보임)')
    _hearts_line(check, said, balance)
    return check.result('하트 줄은 15b 시트에서 읽음 — 지금 히어로에는 하트 숫자가 없다(시나리오와 다름)')


def p_me_02(run, phone):
    check = Check()
    account, token = _home(run)
    me = account['id']
    _add_avatar(run, account)  # ready 2장이라야 15b 시트가 보유 하트 줄을 보인다(1장이면 무료 시트)
    status, got = tools.rest(run.cfg, run.key, 'DELETE', f'entitlements?profile_id=eq.{me}')
    if status >= 300:
        raise Blocked(f'entitlements 지우기 {status} {got}')
    if _rows(run, f'entitlements?profile_id=eq.{me}&select=heart_balance'):
        raise Blocked('준비: entitlements 행이 안 지워짐 — 0 이 "행 없음" 때문인지 모른다')
    said = _app(check, phone(token_hash=token))
    check.that(said.get('hero') is True, f"히어로 {said.get('hero', MISSING)}(기대 보임)")
    check.that(said.get('load_error') is False, f"불러오기 실패 안내 {said.get('load_error', MISSING)}(기대 없음)")
    _hearts_line(check, said, 0)
    rows = _rows(run, f'entitlements?profile_id=eq.{me}&select=heart_balance')
    check.that(not rows, f'entitlements {len(rows)}행(기대 0 — 화면은 읽기만 한다)')
    return check.result('하트 0 은 15b 시트 줄로 읽음 — 지금 히어로에는 하트 숫자가 없다(시나리오와 다름)')


# ── E-ME-03 · 06 ────────────────────────────────────────────────────────────────────────────────────

def p_me_03(run, phone):
    check = Check()
    _, token = _home(run)
    titles = _app(check, phone(token_hash=token)).get('titles') or {}
    for key, label, want in (('gear', '톱니를 누르면', TITLES['16']), ('preview', '"남이 보는 내 프로필 카드" 줄을 누르면', TITLES['15-4']),
                             ('manage', '"프로필 편집" 줄을 누르면', TITLES['15-5'])):
        check.that(titles.get(key, MISSING) == want, f'{label} 화면 제목 {titles.get(key, MISSING)!r}(기대 {want!r})')
    return check.result()


def _keys(node):
    if isinstance(node, dict):
        for key, value in node.items():
            yield key
            yield from _keys(value)
    elif isinstance(node, list):
        for item in node:
            yield from _keys(item)


def p_me_06(run, phone):
    check = Check()
    number = area2._phone()
    account, token = _home(run, phone_number=number)
    me = account['id']
    kakao = f'kk{uuid.uuid4().hex[:8]}'  # 학번(`e2e{n}`)과 겹치지 않는 값 — 학번은 응답에 실린다
    _patch(run, f'profile_private?profile_id=eq.{me}', {'real_name': REAL_NAME, 'kakao_id': kakao})
    private = _one(run, f'profile_private?profile_id=eq.{me}&select=kakao_id,real_name,phone_number')
    photos = _rows(run, f'profile_photos?profile_id=eq.{me}&select=id')
    empty = [k for k in ('real_name', 'phone_number') if not private.get(k)]
    if empty or not photos:
        raise Blocked(f'준비: {" · ".join(empty) or "실사진"} 이 비어 있어 "없다" 가 증거가 못 된다')
    if (private.get('kakao_id'), private['real_name']) != (kakao, REAL_NAME):
        raise Blocked('준비: 카톡 아이디 · 실명이 넣은 값과 다르다 — 겹치지 않는 고유한 값이어야 "없다" 가 증거가 된다')
    reply = _api(run, 'GET', '/me/card-preview', account['token'])
    check.reply('API GET /me/card-preview', reply, 200)
    if reply[0] == 200:
        text = json.dumps(reply[1], ensure_ascii=False)
        keys = sorted({k for k in _keys(reply[1]) if LEAKY_KEY.search(k)})
        check.that(not keys, f'응답에 비공개 칸 이름 {keys}(기대 0개)')
        values = (('카톡 아이디', private['kakao_id']), ('실명', REAL_NAME), ('전화번호', number), ('전화번호(숫자만)', number.replace('-', '')))
        leaked = [name for name, value in values if value in text]
        check.that(not leaked, f'응답에 비공개 값 {leaked}(기대 0개)')
        check.that('profile-photos' not in text, '응답에 실사진 주소(profile-photos 버킷)')
    said = _app(check, phone(token_hash=token))
    for key, want, label in (('card', True, '15-4 카드'), ('photos', False, '실사진 슬라이더'), ('kakao', False, '카카오 카드'),
                             ('trust', False, '"신뢰 확인 완료"'), ('report', False, '"신고하기" 줄'), ('block', False, '"차단하기" 줄')):
        check.that(said.get(key, MISSING) is want, f'{label} {said.get(key, MISSING)}(기대 {"있음" if want else "없음"})')
    return check.result()


# ── E-ME-08 · 09 ────────────────────────────────────────────────────────────────────────────────────

def _add_photo(run, account, position):
    """실사진 한 장을 DB 로 더한다(Vision · AI 안 부름). 파일은 profile-photos 버킷 `{id}/` 아래라 뒷정리가 같이 지운다."""
    path = f"{account['id']}/e2e-{position}-{uuid.uuid4().hex}.png"
    key = {'apikey': run.key, 'Authorization': f'Bearer {run.key}'}
    sent = tools.call('POST', f"{run.cfg['SUPABASE_URL']}/storage/v1/object/profile-photos/{path}", key, raw=(tools.PHOTO.read_bytes(), 'image/png'))
    if sent[0] >= 300:
        raise Blocked(f'사진 파일 올리기 {sent[0]} {sent[1]}')
    area2._insert(run, 'profile_photos', [{'profile_id': account['id'], 'storage_path': path, 'position': position, 'is_avatar_source': False}],
                  account['id'])


def _photo_rows(run, account):
    return _rows(run, f"profile_photos?profile_id=eq.{account['id']}&select=position")


def _photos_to(run, account, want):
    rows = _photo_rows(run, account)
    if len(rows) > want:
        raise Blocked(f'준비: 사진이 이미 {len(rows)}장 — 기대 {want}장')
    first = max((r['position'] for r in rows), default=-1) + 1
    for position in range(first, first + want - len(rows)):
        _add_photo(run, account, position)
    if (got := len(_photo_rows(run, account))) != want:
        raise Blocked(f'준비: 사진 {got}장(기대 {want}장)')


def p_me_08(run, phone):
    check = Check()
    account, token = _home(run)
    _patch(run, f"profiles?id=eq.{account['id']}", {'height_cm': 178, 'mbti': 'ENFP'})
    _photos_to(run, account, 3)
    profile = _one(run, f"profiles?id=eq.{account['id']}&select=height_cm,mbti,major")
    said = _app(check, phone(token_hash=token))
    check.that(said.get('sections', MISSING) == SECTIONS, f"섹션 순서 {said.get('sections', MISSING)}(기대 {SECTIONS})")
    check.that(said.get('photos', MISSING) == 3, f"실사진 {said.get('photos', MISSING)}장(기대 3장)")
    check.that(said.get('badge') is True, f"실제 사진의 \"수락 후 공개\" 배지 {said.get('badge', MISSING)}(기대 보임)")
    check.that(said.get('photo_note') is True, f"\"서로 수락하면 전달돼요\" {said.get('photo_note', MISSING)}(기대 보임)")
    want = {'내 키': f"{profile['height_cm']}cm", 'MBTI': profile['mbti'], '학과': profile['major']}
    check.that(said.get('facts', MISSING) == want, f"기본 정보 행 {said.get('facts', MISSING)}(기대 {want})")
    return check.result()


def p_me_09(run, phone):
    check = Check()
    for name, fields, age_note, height_note in PREFERENCES:
        account, token = _home(run)
        _patch(run, f"profiles?id=eq.{account['id']}", fields)
        part = Check()
        said = _app(part, phone(token_hash=token), name)
        part.that(said.get('age_note', MISSING) == age_note, f"나이 줄 {said.get('age_note', MISSING)!r}(기대 {age_note!r})")
        part.that(said.get('height_note', MISSING) == height_note, f"키 줄 {said.get('height_note', MISSING)!r}(기대 {height_note!r})")
        check.problems += [f'{name}: {p}' for p in part.problems]
    return check.result()


# ── E-ME-28 · 29 · 30 ───────────────────────────────────────────────────────────────────────────────

def _unlock_line(at):
    """풀리는 날 문구 — 한국 시각의 월 · 일(basic_info_edit_view_model.dart nicknameUnlockText)."""
    kst = at.astimezone(SEOUL)
    return f'{kst.month}월 {kst.day}일부터 바꿀 수 있어요'


def _server_unlock(run, account):
    """GET /me/profile 이 준 풀리는 때(None = 지금 바꿀 수 있음) — 앱이 읽는 값과 같은 출처."""
    status, body = _api(run, 'GET', '/me/profile', account['token'])[:2]
    if status != 200:
        raise Blocked(f'GET /me/profile {status}')
    at = (body or {}).get('nickname_changeable_at')
    return _at(at) if at else None


def _lock_reading(run, phone, changed_at):
    """계정 하나에 nickname_changed_at 을 넣고 15-6 을 연 앱의 말을 읽는다 → (Check, 앱의 말, 서버가 준 풀리는 때)."""
    account, token = _home(run)
    _patch(run, f"profiles?id=eq.{account['id']}", {'nickname_changed_at': changed_at.isoformat()})
    unlock, want = _server_unlock(run, account), changed_at + NICKNAME_INTERVAL
    if (unlock is None) != (want <= _now()) or (unlock is not None and abs(unlock - want) > timedelta(seconds=1)):
        raise Blocked(f'준비: 서버가 준 풀리는 때 {unlock} — 넣은 값 + 30일({want})과 다르다')
    part = Check()
    said = _app(part, phone(token_hash=token))
    if unlock is not None and _now() >= unlock:
        raise Blocked(f'잠금이 풀리는 때({unlock})가 앱이 읽는 사이에 지났다 — 판정 못 함')
    return part, said, unlock


def _judge_lock(part, said, unlock, utc_line=None):
    """잠겼으면 닉네임 칸 꺼짐 + 풀리는 날 문구, 풀렸으면 칸 켜짐 + 문구 없음. 키 칸은 늘 켜져 있다."""
    locked = unlock is not None
    part.that(said.get('nickname_enabled', MISSING) is (not locked), f"닉네임 칸 켜짐 {said.get('nickname_enabled', MISSING)}(기대 {not locked})")
    want = _unlock_line(unlock) if locked else None
    got = said.get('unlock_text', MISSING)
    part.that(got == want, f'풀리는 날 문구 {got!r}(기대 {want!r}' + (' — UTC 날짜 그대로' if utc_line and got == utc_line else '') + ')')
    part.that(said.get('height_enabled') is True, f"키 칸 켜짐 {said.get('height_enabled', MISSING)}(기대 True)")


def p_me_28(run, phone):
    part, said, unlock = _lock_reading(run, phone, _now() - timedelta(days=10))
    _judge_lock(part, said, unlock)
    return part.result()


def p_me_29(run, phone):
    check = Check()
    for name, ago in (('풀린 쪽(30일 + 2분 전)', NICKNAME_INTERVAL + timedelta(minutes=2)),
                      ('잠긴 쪽(30일 − 2분 전)', NICKNAME_INTERVAL - timedelta(minutes=2))):
        part, said, unlock = _lock_reading(run, phone, _now() - ago)
        _judge_lock(part, said, unlock)
        check.problems += [f'{name}: {p}' for p in part.problems]
    return check.result()


def p_me_30(run, phone):
    # 풀리는 순간 = 오늘 + 20일 16:00 UTC = 한국 다음 날 01:00 — UTC 날짜와 한국 날짜가 하루 다르다
    changed = _now().replace(hour=16, minute=0, second=0, microsecond=0) - timedelta(days=10)
    part, said, unlock = _lock_reading(run, phone, changed)
    utc = unlock.astimezone(timezone.utc)
    _judge_lock(part, said, unlock, f'{utc.month}월 {utc.day}일부터 바꿀 수 있어요')
    return part.result()


# ── E-WD-01 · 03 · 17 ───────────────────────────────────────────────────────────────────────────────

def p_wd_01(run, phone):
    check = Check()
    account, token = _home(run)
    blocks = _signup_blocks(run)
    said = _app(check, phone(token_hash=token))
    check.that(said.get('title') is True, f"1차 시트 제목 \"정말 떠나시나요?\" {said.get('title', MISSING)}(기대 보임)")
    check.that(said.get('lead') is True, f"안내 \"탈퇴하면 아래 내용이 삭제돼요\" {said.get('lead', MISSING)}(기대 보임)")
    check.that(said.get('items', MISSING) == DELETED, f"지워지는 항목 {said.get('items', MISSING)}(기대 {DELETED})")
    check.that(said.get('warning') is True, f"경고 \"재가입은 2개월 뒤에 가능해요\" {said.get('warning', MISSING)}(기대 보임)")
    check.that(said.get('buttons', MISSING) == ['영구 삭제'], f"시트의 버튼 {said.get('buttons', MISSING)}(기대 [영구 삭제])")
    _unchanged(run, account, check, blocks, '1차 시트')
    return check.result()


def p_wd_03(run, phone):
    check = Check()
    account, token = _home(run)
    blocks = _signup_blocks(run)
    said = _app(check, phone(token_hash=token))
    check.that(said.get('final_seen') is True, f"최종 시트 {said.get('final_seen', MISSING)}(기대 보임)")
    check.that(said.get('final_buttons', MISSING) == ['정말 영구 삭제'],
               f"최종 시트의 버튼 {said.get('final_buttons', MISSING)}(기대 [정말 영구 삭제] — 이 버튼은 안 누른다)")
    check.that(said.get('closed') is True, f"취소 뒤 시트 닫힘 {said.get('closed', MISSING)}(기대 True)")
    check.that(said.get('title') == TITLES['16'], f"취소 뒤 화면 {said.get('title', MISSING)!r}(기대 {TITLES['16']!r})")
    _unchanged(run, account, check, blocks, '취소')
    return check.result()


def p_wd_17(run, phone):
    check = Check()
    account, token = _home(run)
    _suspend(run, account)
    blocks = _signup_blocks(run)
    said = _app(check, phone(token_hash=token))
    check.that(said.get('buttons', MISSING) == ['로그아웃'], f"정지 화면의 버튼(AppButton) {said.get('buttons', MISSING)}(기대 [로그아웃] 1개)")
    check.that(said.get('withdraw_link') is True, f"글자 버튼 \"탈퇴하기\" {said.get('withdraw_link', MISSING)}(기대 있음 — A5)")
    check.that(said.get('sheet') is True, f"\"탈퇴하기\" 를 누르면 14f-1 시트 \"정지 중에 탈퇴할까요?\" {said.get('sheet', MISSING)}(기대 뜸)")
    check.that(said.get('warning') is True, f"14f-1 경고 \"다시 가입할 수 없어요\"(무기한 제한) {said.get('warning', MISSING)}(기대 보임)")
    _unchanged(run, account, check, blocks, '정지 화면', status='suspended')
    return check.result('시나리오(탈퇴 입구 없음 · 로그아웃뿐)와 다르다 — 글자 버튼 "탈퇴하기"(A5)가 있고 누르면 14f-1 시트가 뜬다. '
                        'AppButton 은 로그아웃 1개. 정지 계정이 다른 화면으로 못 가는 것은 E-SAFE-50 이 본다')


# ── E-EDGE-13 · 14 · 16 · 23 ────────────────────────────────────────────────────────────────────────

def p_edge_13(run, phone):
    check = Check()
    account, token = _home(run)
    before = _saved(run, account)
    pressed = []
    said = _app(check, phone(midway=stepper(phone, *[_press_back(phone, pressed)] * len(EDGE_13)), token_hash=token))
    want = [step for step, *_ in EDGE_13]
    check.that(pressed == want, f'앱이 멈춘 화면 {pressed}(기대 {want})')
    walks = {w.get('step'): w for w in said.get('walks') or []}
    for step, opened, arrival, label in EDGE_13:
        walk = walks.get(step, {})
        check.that(walk.get('opened', MISSING) == TITLES[opened], f"{label}: 연 화면 앱바 {walk.get('opened', MISSING)!r}(기대 {TITLES[opened]!r})")
        if step not in NO_VALUE_TO_EDIT:
            check.that(walk.get('edited') is True, f"{label}: 값을 고친 상태 {walk.get('edited', MISSING)}(기대 True)")
        check.that(walk.get('title', MISSING) == TITLES[arrival], f"{label}: 뒤로 뒤 앱바 {walk.get('title', MISSING)!r}(기대 {TITLES[arrival]!r})")
        check.that(walk.get('asked') is False, f"{label}: 뒤로 뒤 묻는 창 {walk.get('asked', MISSING)}(기대 0번)")
    check.that(_saved(run, account) == before, '뒤로 나간 뒤 DB 가 바뀜(저장 안 한 값이 저장됨)')
    return check.result('15-5 · 15-4 는 고칠 값이 없어 열기만 했다(시나리오는 "각각 값을 고친 상태")')


def p_edge_14(run, phone):
    check = Check()
    account, token = _home(run)
    blocks, avatars = _signup_blocks(run), _avatar_rows(run, account)
    pressed = []
    said = _app(check, phone(midway=stepper(phone, *[_press_back(phone, pressed)] * len(EDGE_14)), token_hash=token))
    want = [step for step, *_ in EDGE_14]
    check.that(pressed == want, f'앱이 멈춘 시트 {pressed}(기대 {want})')
    sheets = {s.get('step'): s for s in said.get('sheets') or []}
    for step, arrival, label, other in EDGE_14:
        sheet = sheets.get(step, {})
        check.that(sheet.get('open_before') is True, f"{label}: 뒤로 전 시트 {sheet.get('open_before', MISSING)}(기대 떠 있음)")
        check.that(sheet.get('open_after') is False, f"{label}: 뒤로 뒤 시트 {sheet.get('open_after', MISSING)}(기대 닫힘)")
        check.that(sheet.get('title', MISSING) == TITLES[arrival], f"{label}: 뒤로 뒤 화면 {sheet.get('title', MISSING)!r}(기대 {TITLES[arrival]!r} 그대로)")
        if other:
            check.that(sheet.get(other) is False, f"{label}: 뒤로 뒤 다른 시트({other}) {sheet.get(other, MISSING)}(기대 안 열림)")
    check.that(_avatar_rows(run, account) == avatars, '시스템 뒤로 뒤 아바타 행이 바뀜(다시 만들기 요청이 갔다)')
    _unchanged(run, account, check, blocks, '시스템 뒤로')
    return check.result()


def p_edge_16(run, phone):
    check = Check()
    account, token = _signed_in(run, 'new')  # 약관 동의 전
    consents = f"user_consents?profile_id=eq.{account['id']}&select=kind"
    if _rows(run, consents):
        raise Blocked('준비: 동의 전 계정인데 동의 행이 있다')
    tops = []

    def back(said):
        tools.adb(phone.serial, *BACK)
        time.sleep(1.5)  # 뒤로가 먹었다면 앱이 내려가는 시간
        tops.append(phone.top())

    said = _app(check, phone(midway=stepper(phone, back), token_hash=token))
    top = tops[0] if tops else ''
    check.that(tools.PACKAGE in top, f'뒤로 뒤 맨 앞 화면이 우리 앱이 아님({top[:90]!r})')
    check.that(said.get('on_consent') is True, f"뒤로 뒤 02-c {said.get('on_consent', MISSING)}(기대 그대로)")
    rows = _rows(run, consents)
    check.that(not rows, f'동의 행 {len(rows)}개(기대 0 — 뒤로는 동의가 아니다)')
    return check.result()


def p_edge_23(run, phone):
    check = Check()
    _, token = _home(run)
    said = _app(check, phone(token_hash=token))
    if check.problems:
        return check.result()
    before = said.get('before', MISSING)
    if before != TITLES['15-5']:
        raise Blocked(f'두 번째 누름이 15-5 가 아닌 화면({before!r})에 닿음 — 판정 못 함')
    layers = 2 if said.get('manage_again') is True else 1 if said.get('on_profile') is True else None
    check.that(layers is not None, f"뒤로 한 번 뒤 도착 화면을 모르겠다(앱바 {said.get('title', MISSING)!r}) — 15 도 15-5 도 아님")
    if layers is None:
        return check.result()
    return check.result(f"{layers}겹 — 뒤로 한 번 뒤 {'15 로 돌아옴' if layers == 1 else '15-5 가 또 나옴'}(쌓인 15-5 {said.get('stacked', MISSING)}개). "
                        '막는 코드 없음(my_profile_screen.dart context.push)이라 결과 기록')


PHONE = {
    'E-ME-01': p_me_01, 'E-ME-02': p_me_02, 'E-ME-03': p_me_03, 'E-ME-06': p_me_06, 'E-ME-08': p_me_08, 'E-ME-09': p_me_09,
    'E-ME-28': p_me_28, 'E-ME-29': p_me_29, 'E-ME-30': p_me_30,
    'E-WD-01': p_wd_01, 'E-WD-03': p_wd_03, 'E-WD-17': p_wd_17,
    'E-EDGE-13': p_edge_13, 'E-EDGE-14': p_edge_14, 'E-EDGE-16': p_edge_16, 'E-EDGE-23': p_edge_23,
}

area1.PHONE.update(PHONE)
area1.BUNDLES['area5-read'] = list(PHONE)
tools.CASE_LIMITS.update({'E-EDGE-13': 600, 'E-EDGE-14': 480})  # 멈춤이 일곱 · 셋 — 멈춤마다 앱이 화면을 열고 닫는다
