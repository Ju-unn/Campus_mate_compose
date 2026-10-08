"""영역 5 폰 A 한 대 · 화면 읽기 16개(E-ME · E-WD · E-EDGE)의 PC 쪽 시험 — 폰 · 운영 없이 가짜 앱 · 가짜 서버로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area5_read`.

가짜 서버([ReadFake])는 영역 3 안전 시험의 [PhoneFake](신고 · 차단 · 정지 · 닉네임)에 이 묶음이 읽는 것 — 프로필 칸 · 아바타 · 사진 · 하트 장부 ·
비공개 칸 · 풀리는 때(GET /me/profile) · 15-4 응답(GET /me/card-preview) — 만 더했다. 가짜 앱은 test_area3_phone.py 의 App(한 번 켜서 한 번 말함),
시스템 뒤로를 보내는 가설은 [StepApp](step 을 차례로 말하고 PC 가 부르는 것을 사건 목록에 남김). 계정은 만든 순서대로 id-1 · id-2 …, 토큰은 tok-1 ….
시험의 글자는 모듈에서 가져오지 않고 그대로 적었다 — 모듈의 상수가 틀려도 시험이 잡는다.
"""

import ast
import json
import re
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock

from e2e import area1, area2, area2_phone3, area5_read, notify, tools
from e2e.area1 import SEOUL
from e2e.test_area1 import CFG
from e2e.test_area3_phone import App, said
from e2e.test_area3_phone2 import as_fn
from e2e.test_area3_safe import _who
from e2e.test_area3_safe_phone import PhoneFake
from e2e.tools import Reply, Run
from e2e.fake_regen_photo import patch_regen_photo

BUNDLE = ['E-ME-01', 'E-ME-02', 'E-ME-03', 'E-ME-04', 'E-ME-06', 'E-ME-08', 'E-ME-09', 'E-ME-28', 'E-ME-29', 'E-ME-30',
          'E-WD-01', 'E-WD-03', 'E-WD-17', 'E-EDGE-13', 'E-EDGE-14', 'E-EDGE-16', 'E-EDGE-23']
UNIVERSITY = '테스트대학'
STARTER = 5  # 가짜 서버가 홈 계정에 처음부터 넣어 두는 하트 — "행을 지웠다 · 잔액을 DB 값으로 읽었다" 가 의미 있게
OURS = 'topResumedActivity=ActivityRecord{1 u0 io.github.juunn.campusmate/.MainActivity t9}'
LAUNCHER = 'topResumedActivity=ActivityRecord{1 u0 com.sec.android.app.launcher/.Launcher t1}'
BACK = ('S', 'shell', 'input', 'keyevent', 'KEYCODE_BACK')
TITLES = {'15': '내 프로필', '15-4': '남이 보는 내 프로필', '15-5': '프로필 편집', '15c': '자기소개·태그 수정',
          '06-1': '이상형 조건 수정', 'tag': '관심사 수정', '15-6': '기본 정보 수정', '15-7': '사진 수정', '16': '설정'}
SECTIONS = ['실제 사진', '기본 정보', '선호 조건', '자기소개']
DELETED = ['프로필과 인증 정보', '수락 매칭 기록', '모든 대화 내용']
EN_DASH = '–'
EDGE_13 = [('15-5', '15-5', '15'), ('15-4', '15-4', '15'), ('15c', '15c', '15-5'), ('06-1', '06-1', '15-5'),
           ('tag', 'tag', '15c'), ('15-6', '15-6', '15-5'), ('15-7', '15-7', '15-5')]
EDITED = {'15c', '06-1', 'tag', '15-6', '15-7'}  # 15-5 · 15-4 는 고칠 값이 없다 — 열기만
TYPED = {'15c', '15-6'}  # 글자를 넣은 화면 — 앱이 뒤로 전에 포커스를 풀어 키보드를 닫는다
STOPS = [s for s, _, _ in EDGE_13] + ['end']  # EDGE-13 앱이 멈추는 차례 — 끝 멈춤 'end' 에서는 뒤로를 안 보낸다
# 뒤로 나간 뒤에도 같아야 하는 프로필 칸 — 모듈의 SAVED 와 같은 열일곱 칸(시험이 따로 적는다: 모듈에서 칸이 빠지면 여기서 잡힌다)
SAVED_COLUMNS = ['nickname', 'nickname_changed_at', 'bio', 'height_cm', 'mbti', 'major', 'interest_tags', 'my_traits', 'ideal_traits',
                 'preferred_age_min', 'preferred_age_max', 'preferred_height_min', 'preferred_height_max', 'preferred_mbti_flags',
                 'preferred_animal_types', 'preferred_impression_types', 'status']


def now():
    return datetime.now(timezone.utc)


def columns(select):
    """PostgREST select 의 칸 이름들 — `universities(name)` 같은 끼움은 이름만."""
    out, depth, current = [], 0, ''
    for char in select:
        depth += (char == '(') - (char == ')')
        if char == ',' and depth == 0:
            out.append(current)
            current = ''
        else:
            current += char
    return [c.split('(')[0].strip() for c in out + [current] if c.strip()]


def server_keys(path, function):
    """서버 소스에서 [function] 이 돌려주는 dict 리터럴의 문자열 키 — 가짜 서버가 진짜 응답 칸을 빠뜨리지 않았는지 맞대 본다."""
    tree = ast.parse((tools.ROOT / 'backend' / 'app' / path).read_text(encoding='utf-8'))
    node = next(n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name == function)
    returned = next(n for n in ast.walk(node) if isinstance(n, ast.Return) and isinstance(n.value, ast.Dict))
    return [k.value for k in returned.value.keys if isinstance(k, ast.Constant)]


DART_FILES = ('area5.dart', 'area5_read.dart')
ALLOWED_BUTTONS = ('_withdraw', '_deleteForever')  # 앱 쪽이 `button(…)` 으로 누를 수 있는 라벨 상수 둘 — 탈퇴하기 · 1차 시트의 영구 삭제(최종 시트를 연다)


def delete_button_violations(text):
    """앱 쪽 dart 가 탈퇴 버튼("정말 영구 삭제")을 누를 길이 생겼는지 — 주석을 뺀 코드에서 본다.
    a: 그 글자가 든 코드 줄(상수 선언 포함 — 상수에 담아 누르는 우회를 막는다) · b: 최종 시트(WithdrawFinalSheet)나 형(AppButton)으로 누르는 문장 ·
    b2: `tap(…button(라벨))` 의 라벨이 허락된 상수 둘이 아님 · c: '영구 삭제' 가 든 다른 코드 줄(새 상수가 생기면 알린다)."""
    code = '\n'.join(re.sub(r'//.*$', '', line) for line in text.replace('\r\n', '\n').split('\n'))
    found = []
    for number, line in enumerate(code.split('\n'), 1):
        if '정말 영구 삭제' in line:
            found.append((f'a:{number}', line.strip()))
        elif '영구 삭제' in line and not re.match(r"\s*const _deleteForever = '영구 삭제';\s*$", line):
            found.append((f'c:{number}', line.strip()))
    for statement in code.split(';'):
        if not re.search(r'\btap\(', statement):
            continue
        if 'WithdrawFinalSheet' in statement or 'AppButton' in statement:
            found.append(('b', ' '.join(statement.split())))
        found += [('b2', ' '.join(statement.split())) for argument in re.findall(r'\bbutton\(([^()]*)\)', statement)
                  if argument.strip() not in ALLOWED_BUTTONS]
    return found


def unlock_line(at):
    kst = at.astimezone(SEOUL)
    return f'{kst.month}월 {kst.day}일부터 바꿀 수 있어요'


class ReadFake(PhoneFake):
    """PhoneFake + 이 묶음이 읽는 것. 응답은 진짜 서버의 칸을 그대로 갖고(backend me/router.py · cards/router.py — [FakeShapeTest] 가 맞대 본다),
    GET 은 PostgREST 처럼 요청한 `select=` 칸만 · `order=` 순서로 돌려준다. 홈 계정은 처음부터 하트 [STARTER] 를 가진다."""

    def __init__(self):
        super().__init__()
        self.leak = None  # GET /me/card-preview 가 새로 흘릴 칸 — (비공개 행) → dict
        self.ignore_lock = False  # 잠금을 모르는 서버
        self.lock_shift = timedelta(0)  # 풀리는 때를 이만큼 어긋나게 주는 서버
        self.starter = STARTER
        self.no_phone = False  # 04-1 이 전화번호를 저장하지 못한 세상
        self._stamp = datetime.min.replace(tzinfo=timezone.utc)  # 마지막으로 찍은 created_at
        for method, pattern, handler in (
                ('GET', r'/me/profile', self._me_profile), ('GET', r'/me/card-preview', self._preview),
                ('POST', r'/school-info', self._school), ('POST', r'/profile-onboarding/kakao-id', self._kakao),
                ('POST', r'/profile-onboarding/photos', self._photo), ('POST', r'/rest/v1/rpc/grant_hearts', self._grant)):
            self.on(method, pattern, handler)

    def profile(self, pid):
        fresh = pid not in self.profiles
        row = super().profile(pid)
        if fresh:
            row.update({'universities': {'name': UNIVERSITY}, 'major': None, 'birth_year': None, 'height_cm': None, 'mbti': None,
                        'nickname': None, 'nickname_changed_at': None, 'withdrawn_at': None, 'bio': '소개', 'student_number': None,
                        'preferred_age_min': 20, 'preferred_age_max': 30, 'preferred_height_min': None, 'preferred_height_max': None,
                        'interest_tags': ['카페가기', '자전거', '패션'], 'my_traits': ['깨끗한 피부'], 'ideal_traits': ['연상'],
                        'preferred_mbti_flags': {}, 'preferred_animal_types': ['dog'], 'preferred_impression_types': ['kind']})
        return row

    def private(self, pid):
        return next(r for r in self.rows('profile_private') if r['profile_id'] == pid)

    def _basic(self, sent):
        body, who = sent['body'], _who(sent)
        self.profile(who).update(birth_year=body['birth_year'], height_cm=body['height_cm'], mbti=body['mbti'])
        self.rows('profile_private').append({'profile_id': who, 'kakao_id': None, 'real_name': None, 'phone_number': None if self.no_phone else '\\x3031',
                                             'phone_plain': body['phone_number']})
        return super()._basic(sent)

    def _bio(self, sent):
        self.rows('entitlements').append({'profile_id': _who(sent), 'heart_balance': self.starter})
        return super()._bio(sent)

    def _school(self, sent):
        # 진짜 서버처럼 학번도 저장한다 — 계정 공장은 학번과 카톡 아이디를 같은 `e2e{n}` 으로 넣는다(tools.py:587 · 591).
        self.profile(_who(sent)).update(major=sent['body']['department'], student_number=sent['body']['student_number'])
        return Reply(200, {})

    def _kakao(self, sent):
        self.private(_who(sent))['kakao_id'] = sent['body']['kakao_id']
        return Reply(200, {})

    def _photo(self, sent):
        who = _who(sent)
        position = len([p for p in self.rows('profile_photos') if p['profile_id'] == who])
        self.rows('profile_photos').append({'id': str(len(self.rows('profile_photos'))), 'profile_id': who, 'position': position,
                                            'storage_path': f'{who}/p{position}.png', 'is_avatar_source': position == 0})
        return Reply(200, {})

    def _grant(self, sent):
        body = sent['body']
        row = next((r for r in self.rows('entitlements') if r['profile_id'] == body['p_profile_id']), None)
        if row is None:
            self.rows('entitlements').append({'profile_id': body['p_profile_id'], 'heart_balance': body['p_amount']})
        else:
            row['heart_balance'] += body['p_amount']
        return Reply(200, None)

    def _ready(self, who):
        return [a for a in self.rows('profile_avatars') if a['profile_id'] == who and a['status'] == 'ready']

    def _avatar_url(self, who):
        latest = max(self._ready(who), key=lambda a: a['created_at'], default=None)
        return latest and f"https://sb.test/storage/v1/object/public/avatars/{latest['storage_path']}"

    def _age(self, row):
        return datetime.now(SEOUL).year - row['birth_year'] + 1 if row['birth_year'] is not None else None

    def _me_profile(self, sent):
        """GET /me/profile — backend/app/me/router.py get_my_profile 의 칸 그대로."""
        who = _who(sent)
        row = self.profile(who)
        at = row['nickname_changed_at']
        unlock = datetime.fromisoformat(at) + timedelta(days=30) if at else None
        locked = unlock + self.lock_shift if unlock and unlock > now() and not self.ignore_lock else None
        photos = sorted((p for p in self.rows('profile_photos') if p['profile_id'] == who), key=lambda p: p['position'])
        urls = [f"https://sb.test/storage/v1/object/sign/profile-photos/{p['storage_path']}" for p in photos]
        balance = next((e['heart_balance'] for e in self.rows('entitlements') if e['profile_id'] == who), 0)
        return Reply(200, {
            'nickname': row['nickname'], 'age': self._age(row), 'university': row['universities']['name'], 'major': row['major'],
            'height_cm': row['height_cm'], 'mbti': row['mbti'], 'avatar_url': self._avatar_url(who), 'photo_urls': urls,
            'preferred_age_min': row['preferred_age_min'], 'preferred_age_max': row['preferred_age_max'],
            'preferred_height_min': row['preferred_height_min'], 'preferred_height_max': row['preferred_height_max'],
            'bio': row['bio'], 'interest_tags': row['interest_tags'], 'my_traits': row['my_traits'], 'ideal_traits': row['ideal_traits'],
            'preferred_mbti_flags': row['preferred_mbti_flags'], 'preferred_animal_types': row['preferred_animal_types'],
            'preferred_impression_types': row['preferred_impression_types'],
            'photos': [{'id': p['id'], 'url': url, 'is_avatar_source': p['is_avatar_source']} for p, url in zip(photos, urls)],
            'heart_balance': balance, 'avatar_regen_cost': 0 if len(self._ready(who)) <= 1 else 10,
            'nickname_changeable_at': locked and locked.isoformat()})

    def _preview(self, sent):
        """GET /me/card-preview — cards/router.py profile_detail · _card_profile 의 칸 그대로(학번까지 싣는다)."""
        who = _who(sent)
        row = self.profile(who)
        body = {'profile': {'profile_id': who, 'nickname': row['nickname'], 'age': self._age(row), 'university': row['universities']['name'],
                            'major': row['major'], 'avatar_url': self._avatar_url(who)},
                'survey': [0.5] * 9, 'animal_type': 'dog', 'impression_type': 'kind', 'religion': 'none', 'is_smoker': False,
                'interests': row['interest_tags'], 'my_traits': row['my_traits'], 'ideal_traits': row['ideal_traits'],
                'height_cm': row['height_cm'], 'mbti': row['mbti'], 'student_number': row['student_number'], 'bio': row['bio'],
                'ideal_note': None}
        if self.leak:
            body = {**body, **self.leak(self.private(who))}
        return Reply(200, body)

    def _table(self, method, name, sent):
        if method == 'POST' and name == 'profile_avatars':
            for row in sent['body'] if isinstance(sent['body'], list) else [sent['body']]:
                # 늘 앞 행보다 늦게 — 윈도 시계는 잇따른 두 호출에 같은 시각을 줄 수 있어 "늦은 쪽" 이 갈리지 않는다(10% 안팎 간헐 실패였다)
                self._stamp = max(now(), self._stamp + timedelta(microseconds=1))
                row.setdefault('created_at', self._stamp.isoformat())
        reply = super()._table(method, name, sent)
        if method != 'GET' or reply[0] != 200 or not isinstance(reply[1], list):
            return reply
        rows, query = reply[1], sent['query']
        if 'order' in query:  # PostgREST: `order=칸` 또는 `order=칸.desc`
            column, _, direction = query['order'].partition('.')
            rows = sorted(rows, key=lambda r: str(r.get(column)), reverse=direction == 'desc')
        if query.get('select') and query['select'] != '*':  # 요청한 칸만 — 없는 칸은 null
            rows = [{c: r.get(c) for c in columns(query['select'])} for r in rows]
        return Reply(200, rows)


class StepApp(App):
    """stepper 가 부르는 phone.hub(go · wait) · serial · top 을 가진 가짜 앱 — [steps] 를 차례로 말하고(첫 말은 midway 로) 끝에 answer 를 돌려준다.
    [events] 에 'step:<이름>' · 'go' 를 남긴다(PC 가 adb 로 뒤로를 보낸 것은 시험이 'back' 으로 같은 목록에 적는다).
    [port] 는 Hub 의 PC 쪽 포트 — 오프라인 가설이 끝에 adb reverse 를 다시 걸 때 읽는다(area2_phone3.offline)."""

    port = 8765

    def __init__(self, answer, steps, events, top=OURS):
        super().__init__(answer)
        self.steps, self.events, self.serial, self.hub, self._top = list(steps), events, 'S', self, top
        self.later = list(steps[1:])

    def top(self):
        self.events.append('top')
        return self._top

    def go(self, extra=None):
        self.events.append('go')

    def wait(self, timeout):
        if not self.later:
            return {'result': 'pass'}  # 더 멈출 줄 알았는데 앱이 끝났다
        name = self.later.pop(0)
        self.events.append(f'step:{name}')
        return {'step': name}

    def __call__(self, midway=None, **job):
        self.jobs.append(job)
        if midway:
            self.events.append(f'step:{self.steps[0]}')
            midway({'step': self.steps[0]})
            self.events.append('go')  # 마지막 go 는 Run.phone 이 넣는다
        return self.answer(job)


class Sequence:
    """앱을 두 번 켜는 가설 — 켤 때마다 다음 말을 한다(판마다 계정을 새로 만든다)."""

    def __init__(self, *answers):
        self.answers = list(answers)

    def __call__(self, job):
        answer = self.answers.pop(0)
        return answer(job) if callable(answer) else dict(answer)


class ReadBase(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.run_ = Run(self.root / 'area5-read', 'b', cfg={**CFG}, key='svc')
        self.fake = ReadFake()
        self.events, self.adb_calls = [], []
        self.regen_calls = patch_regen_photo(self, area5_read, when=lambda: len(self.fake.sent))  # 사진 옮기기 대신 부른 때만 적는다

        def fake_adb(serial, *args, check=True):
            self.adb_calls.append((serial, *args))
            if args[-1] == 'KEYCODE_BACK':
                self.events.append('back')
            return ''

        # accounts.json 을 계정 단계마다 열고 쓰는 것이 느리다(가설은 읽지 않는다) — 쓰기 가드는 가짜 서버가 만든 계정 id 만 쓰는지로 따로 본다([writes_only_mine]).
        for patcher in (mock.patch.object(tools, 'call', self.fake), mock.patch.object(tools, 'adb', fake_adb),
                        mock.patch.object(area5_read.time, 'sleep'), mock.patch.object(Run, 'shot'), mock.patch.object(Run, 'remember'),
                        mock.patch.object(area2, '_guard'), mock.patch.object(area2_phone3, '_guard')):
            patcher.start()
            self.addCleanup(patcher.stop)

    def case(self, name, answer, app=None):
        """가설 하나를 깨끗한 가짜 서버에서 — 계정은 늘 id-1 부터. [answer] 는 앱의 말(dict 또는 일감 → dict)."""
        fake = self.fake
        for table in (fake.tables, fake.statuses, fake.profiles, fake.phones):
            table.clear()
        fake.sent.clear()
        fake.users.clear()
        fake.verifies = fake._ids = 0
        self.events.clear()
        self.adb_calls.clear()
        app = app or App(as_fn(answer))
        return area1.attempt_phone(self.run_, name, app), app

    def passes(self, name, answer, app=None):
        (result, note), app = self.case(name, answer, app)
        self.assertEqual(result, 'pass', note)
        return note, app

    def fails(self, name, answer, *words, app=None):
        (result, note), app = self.case(name, answer, app)
        self.assertEqual(result, 'fail', note)
        for word in words:
            self.assertIn(word, note)
        return note

    def blocked(self, name, answer, *words, app=None):
        (result, note), app = self.case(name, answer, app)
        self.assertEqual(result, 'blocked', note)
        for word in words:
            self.assertIn(word, note)
        return note

    def profile(self, n=1):
        return self.fake.profile(f'id-{n}')

    def rows(self, table, **where):
        return [r for r in self.fake.rows(table) if all(r.get(k) == v for k, v in where.items())]

    def fail_next(self, method, pattern, status=500):
        self.fake.handlers.insert(0, (method, re.compile(pattern), Reply(status, {'message': 'down'})))

    def second_avatar(self, reply):
        """계정 공장의 첫 아바타는 정상으로, 그 뒤 더하는 아바타 행 넣기는 [reply] 로."""
        handler = lambda sent: reply if self.rows('profile_avatars') else self.fake._table('POST', 'profile_avatars', sent)
        self.fake.handlers.insert(0, ('POST', re.compile(r'/rest/v1/profile_avatars'), handler))

    def writes_only_mine(self):
        """DB 쓰기(POST · PATCH · DELETE)가 이번 실행이 만든 계정 id 만 가리킨다 — 남의 행에 쓰지 않는다."""
        mine = {u['id'] for u in self.fake.users}
        for sent in self.fake.sent:
            if sent['method'] in ('POST', 'PATCH', 'DELETE') and sent['path'].startswith('/rest/v1/'):
                ids = set(re.findall(r'id-\d+', json.dumps([sent['query'], sent['body']], ensure_ascii=False, default=str)))
                self.assertLessEqual(ids, mine, sent['path'])

    def swallow(self, method, pattern):
        """맞는 요청에 204 만 답하고 아무것도 안 바꾼다 — 지우지 못한 서버."""
        self.fake.handlers.insert(0, (method, re.compile(pattern), Reply(204, None)))


class RegistryTest(unittest.TestCase):
    def test_bundle_is_the_sixteen_in_the_order_of_the_scenario(self):
        self.assertEqual(area1.BUNDLES['area5-read'], BUNDLE)
        self.assertEqual(list(area5_read.PHONE), BUNDLE)
        self.assertLessEqual(set(BUNDLE), set(area1.PHONE))

    def test_the_runner_sees_the_bundle(self):
        # 새 인터프리터로 — 이 시험 파일이 area5_read 를 먼저 들여오면 진행 프로그램이 안 들여와도 통과해 버린다.
        probe = 'from e2e import __main__ as m, area1; print(m.BUNDLES.get("area5-read"), "E-ME-01" in area1.PHONE)'
        out = subprocess.run([sys.executable, '-c', probe], cwd=tools.ROOT, capture_output=True, text=True, check=True).stdout
        self.assertEqual(out.strip(), f'{BUNDLE} True')

    def dart(self, name):
        return (tools.ROOT / 'frontend' / 'integration_test' / name).read_text(encoding='utf-8')

    def test_the_app_side_has_no_way_to_tap_the_final_delete_button(self):
        # 탈퇴를 실제로 누르는 가설은 이 묶음에 없다 — "정말 영구 삭제" 를 누를 길(글자 · 상수 · 형으로 누르기)이 앱 쪽에 없어야 한다.
        for name in DART_FILES:
            self.assertEqual(delete_button_violations(self.dart(name)), [], name)

    def test_the_guard_catches_each_way_to_press_it_when_a_line_is_added_to_the_real_files(self):
        ways = (
            ('a', "const _gone = '정말 영구 삭제';"),
            ('a', "await tap(tester, button('정말 영구 삭제'));"),
            ('a', "const _x = '정말 영구 삭제';\nawait tap(tester, button(_x));"),  # 상수에 담는 우회 — 선언이 걸린다
            ('b2', "await tap(tester, button('정말 ' + _deleteForever));"),  # 글자 없이 이어 붙이는 우회
            ('b2', "await tap(tester, button(_somethingElse));"),
            ('b', "await tap(tester,\n    find.descendant(of: find.byType(WithdrawFinalSheet), matching: find.byType(AppButton)));"),
            ('b', "await tester.tap(find.byType(AppButton).last);"),  # 형으로 누르기
            ('b', "await tap(tester, find.widgetWithText(AppButton, label));"),
            ('c', "const _foreverToo = '영구 삭제하기';"),  # 새 상수
            ('c', "final label = '영구 삭제';"),
        )
        for name in DART_FILES:
            real = self.dart(name)
            for rule, line in ways:
                with self.subTest(name=name, line=line):
                    found = delete_button_violations(real + '\nvoid probe() {\n' + line + '\n}\n')
                    self.assertTrue(any(kind.startswith(rule) for kind, _ in found), (rule, found))

    def test_the_guard_lets_comments_and_the_two_allowed_buttons_through(self):
        fine = (
            '/// 최종 시트의 "정말 영구 삭제" 는 누르지 않는다.',
            "const _deleteForever = '영구 삭제';",
            'await tap(tester, button(_deleteForever));',
            'await tap(tester, button(_withdraw));',
            'final labels = _buttonLabels(tester, find.byType(WithdrawFinalSheet));  // 읽기만',
            'final buttons = [for (final b in tester.widgetList<AppButton>(find.byType(AppButton))) b.label];',
        )
        self.assertEqual(delete_button_violations('\n'.join(fine)), [])


# ── 나 탭 읽기 ───────────────────────────────────────────────────────────────────────────────────────

class OfflineMeTest(ReadBase):
    def test_04_restores_network_before_retry_and_observes_hero_within_three_seconds(self):
        events = []
        def airplane(serial, on, settle=None):
            events.append('offline' if on else 'online')
        def online(serial):
            events.append('restore')
        app = StepApp(lambda job: said(error_text='잠시 뒤 다시 시도해 주세요', retry_text='다시 시도', hero=True, retry_ms=2500),
                      ['cut', 'restore'], events)
        with mock.patch.object(notify, 'airplane', airplane), mock.patch.object(notify, 'ensure_online', online):
            self.passes('E-ME-04', {}, app)
        self.assertEqual(events, ['step:cut', 'offline', 'go', 'step:restore', 'online', 'go', 'restore'])

    def test_04_fails_on_a_slow_retry_or_a_missing_hero_and_still_restores_the_network(self):
        events = []
        with mock.patch.object(notify, 'airplane', lambda s, on, settle=None: events.append('offline' if on else 'online')), \
                mock.patch.object(notify, 'ensure_online', lambda s: events.append('restore')):
            app = StepApp(lambda job: said(error_text='잠시 뒤 다시 시도해 주세요', retry_text='다시 시도', hero=False, retry_ms=3500),
                          ['cut', 'restore'], events)
            self.fails('E-ME-04', {}, '히어로', '3500ms', app=app)
        self.assertEqual(events[-1], 'restore')


    def test_04_restores_the_network_when_the_app_says_blocked(self):
        events = []
        with mock.patch.object(notify, 'airplane', lambda s, on, settle=None: events.append('offline' if on else 'online')), \
                mock.patch.object(notify, 'ensure_online', lambda s: events.append('restore')):
            app = StepApp(lambda job: {'result': 'blocked', 'note': '못 찾음'}, ['cut', 'restore'], events)
            self.blocked('E-ME-04', {}, '못 찾음', app=app)
        self.assertEqual(events[-1], 'restore')

    def test_04_re_maps_the_mailbox_after_airplane_mode_like_every_other_offline_case(self):
        # 비행기 모드 뒤 adb reverse 가 풀린 기기 대비(area2_phone3.offline) — 통과 · 실패 · blocked 어느 끝에서도 망 다음에 다시 건다.
        reverse = ('S', 'reverse', f'tcp:{tools.DEVICE_PORT}', 'tcp:8765')
        endings = ((self.passes, (said(error_text='잠시 뒤 다시 시도해 주세요', retry_text='다시 시도', hero=True, retry_ms=2500),)),
                   (self.fails, (said(error_text='잠시 뒤 다시 시도해 주세요', retry_text='다시 시도', hero=False, retry_ms=3500), '히어로')),
                   (self.blocked, ({'result': 'blocked', 'note': '못 찾음'}, '못 찾음')))
        for ending, (answer, *words) in endings:
            with self.subTest(ending=ending.__name__):
                events = []
                app = StepApp(lambda job, answer=answer: dict(answer), ['cut', 'restore'], events)
                with mock.patch.object(notify, 'airplane', lambda s, on, settle=None: events.append('offline' if on else 'online')), \
                        mock.patch.object(notify, 'ensure_online', lambda s: events.append('restore')):
                    ending('E-ME-04', {}, *words, app=app)
                self.assertEqual(events[-1], 'restore')
                self.assertEqual(self.adb_calls[-1:], [reverse], self.adb_calls)


class HeroTest(ReadBase):
    def good(self, **over):
        def answer(job):
            row, balance = self.profile(), self.rows('entitlements')[0]['heart_balance']
            newest = max(self.rows('profile_avatars'), key=lambda r: r['created_at'])
            return said(**{
                'name_line': f"{row['nickname']}, {datetime.now(SEOUL).year - row['birth_year'] + 1}",
                'school': f"{UNIVERSITY}\n{row['major']}", 'avatar_file': newest['storage_path'].rsplit('/', 1)[-1],
                'badge': True, 'chip': True,
                'heart_text': f'하트 10개가 차감돼요. 지금 보유한 하트는 {balance}개예요. 새 아바타는 바로 프로필에 반영돼요.',
                'sheet_closed': True, **over})
        return answer

    def test_01_hero_shows_name_age_school_major_latest_avatar_badge_chip_and_the_balance(self):
        _, app = self.passes('E-ME-01', self.good())
        self.assertEqual(app.jobs, [{'token_hash': 'h'}])
        row = self.profile()
        self.assertEqual((row['birth_year'], row['major']), (datetime.now(SEOUL).year - 23, '디자인학과'))
        avatars = sorted(self.rows('profile_avatars'), key=lambda r: r['created_at'])
        self.assertEqual([a['status'] for a in avatars], ['ready', 'ready'])
        gap = datetime.fromisoformat(avatars[1]['created_at']) - datetime.fromisoformat(avatars[0]['created_at'])
        self.assertGreater(gap, timedelta(days=1))  # created_at 이 뚜렷이 다르다
        self.assertEqual(self.rows('entitlements')[0]['heart_balance'], STARTER + 37)  # 있던 하트에 37 을 더했다 — 화면은 DB 값을 읽는다

    def test_01_the_picture_is_the_one_made_last_not_the_one_inserted_last(self):
        # 더한 장(마지막에 넣은 행)이 오래된 쪽이다 — "마지막 행" 을 그리는 앱은 여기서 걸린다.
        self.passes('E-ME-01', self.good())
        inserted_last = self.rows('profile_avatars')[-1]
        newest = max(self.rows('profile_avatars'), key=lambda r: r['created_at'])
        self.assertIsNot(inserted_last, newest)

    def test_01_fails_on_a_wrong_age_school_picture_badge_chip_balance_or_a_sheet_left_open(self):
        for over, word in (({'name_line': 'Aaaaa, 99'}, '이름 줄'), ({'school': UNIVERSITY}, '학교 줄'),
                           ({'avatar_file': 'e2e-old.png'}, '아바타 파일'), ({'badge': False}, '학생 인증'),
                           ({'chip': False}, '상대에게 이렇게 보여요'),
                           ({'heart_text': '지금 보유한 하트는 0개예요'}, '보유 하트'), ({'sheet_closed': False}, '시트')):
            with self.subTest(over):
                self.fails('E-ME-01', self.good(**over), word)

    def test_01_fails_when_the_app_does_not_say_what_it_saw(self):
        self.fails('E-ME-01', said(), '이름 줄')

    def test_01_writes_only_to_the_account_it_made(self):
        self.passes('E-ME-01', self.good())
        self.writes_only_mine()

    def test_01_is_blocked_when_the_second_avatar_cannot_be_added_or_was_dropped_or_the_date_did_not_turn(self):
        self.second_avatar(Reply(500, {'message': 'down'}))
        self.blocked('E-ME-01', self.good(), '아바타 행 넣기')
        self.fake.handlers.pop(0)
        self.second_avatar(Reply(204, None))
        self.blocked('E-ME-01', self.good(), '준비', 'ready 아바타 1장')
        self.fake.handlers.pop(0)
        self.swallow('PATCH', r'/rest/v1/profile_avatars')
        self.blocked('E-ME-01', self.good(), '준비', 'created_at')

    def test_01_is_blocked_when_the_grant_did_nothing_or_the_profile_reads_empty(self):
        self.fake.starter = 0
        self.swallow('POST', r'/rest/v1/rpc/grant_hearts')
        self.blocked('E-ME-01', self.good(), '준비', '하트 0')
        self.fake.handlers.pop(0)
        self.fake.handlers.insert(0, ('GET', re.compile(r'/rest/v1/profiles'), Reply(200, [{}])))
        self.blocked('E-ME-01', self.good(), '준비', '읽은 값이 비어')


class NoHeartsTest(ReadBase):
    def good(self, **over):
        return said(**{'hero': True, 'load_error': False, 'sheet_closed': True,
                       'heart_text': '하트 10개가 필요해요. 지금 보유한 하트는 0개예요.', **over})

    def test_02_without_an_entitlements_row_the_balance_reads_zero_and_the_screen_has_no_error(self):
        _, app = self.passes('E-ME-02', self.good())
        self.assertEqual(app.jobs, [{'token_hash': 'h'}])
        self.assertEqual(self.rows('entitlements'), [])
        self.assertEqual(len(self.rows('profile_avatars')), 2)  # 두 장이라야 15b 시트가 보유 하트 줄을 보인다(1장이면 무료 시트)

    def test_02_fails_on_a_wrong_balance_a_missing_hero_a_load_error_or_a_sheet_left_open(self):
        for over, word in (({'heart_text': '지금 보유한 하트는 5개예요'}, '보유 하트'), ({'hero': False}, '히어로'),
                           ({'load_error': True}, '불러오기 실패'), ({'sheet_closed': False}, '시트')):
            with self.subTest(over):
                self.fails('E-ME-02', self.good(**over), word)

    def test_02_fails_when_the_app_made_the_row(self):
        def creates(job):
            self.fake.rows('entitlements').append({'profile_id': 'id-1', 'heart_balance': 0})
            return self.good()
        self.fails('E-ME-02', creates, 'entitlements')

    def test_02_is_blocked_when_the_row_cannot_be_deleted_or_stays(self):
        self.fail_next('DELETE', r'/rest/v1/entitlements')
        self.blocked('E-ME-02', self.good(), 'entitlements 지우기 500')
        self.swallow('DELETE', r'/rest/v1/entitlements')
        self.blocked('E-ME-02', self.good(), '안 지워짐')


class EntryRowsTest(ReadBase):
    def good(self, **over):
        return said(titles={'gear': '설정', 'preview': '남이 보는 내 프로필', 'manage': '프로필 편집', **over})

    def test_03_gear_goes_to_settings_and_the_two_rows_to_15_4_and_15_5(self):
        _, app = self.passes('E-ME-03', self.good())
        self.assertEqual(app.jobs, [{'token_hash': 'h'}])

    def test_03_fails_on_any_wrong_title_or_none(self):
        for key, word in (('gear', '톱니'), ('preview', '남이 보는'), ('manage', '프로필 편집')):
            with self.subTest(key):
                self.fails('E-ME-03', self.good(**{key: '내 프로필'}), word, "'내 프로필'")
        self.fails('E-ME-03', said(), '톱니', '남이 보는', '프로필 편집')


class CardPreviewTest(ReadBase):
    def good(self, **over):
        return said(**{'card': True, 'photos': False, 'kakao': False, 'trust': False, 'report': False, 'block': False, **over})

    def test_06_the_response_has_no_private_field_and_the_screen_shows_no_real_photo_kakao_trust_or_report_row(self):
        _, app = self.passes('E-ME-06', self.good())
        self.assertEqual(app.jobs, [{'token_hash': 'h'}])
        private = self.fake.private('id-1')
        self.assertEqual(private['real_name'], 'E2E실명확인')
        self.assertTrue(private['kakao_id'])
        asked = [s for s in self.fake.by('GET', '/me/card-preview')]
        self.assertEqual([s['auth'] for s in asked], ['tok-1'])  # 폰 계정 자기 토큰으로

    def test_06_fails_when_the_response_leaks_a_field_a_value_or_a_photo_address(self):
        for name, leak, word in (
                ('칸 이름', lambda p: {'kakao_id': 'x'}, '비공개 칸'),
                ('실명 칸', lambda p: {'real_name': 'x'}, '비공개 칸'),
                ('전화 칸', lambda p: {'phone_number': 'x'}, '비공개 칸'),
                ('사진 칸', lambda p: {'photos': []}, '비공개 칸'),
                ('카톡 값', lambda p: {'note': p['kakao_id']}, '카톡 아이디'),
                ('실명 값', lambda p: {'note': p['real_name']}, '실명'),
                ('전화 값', lambda p: {'note': p['phone_plain']}, '전화번호'),
                ('전화 숫자', lambda p: {'note': p['phone_plain'].replace('-', '')}, '전화번호'),
                ('사진 주소', lambda p: {'note': 'https://sb.test/storage/v1/object/sign/profile-photos/id-1/a.png'}, '실사진 주소')):
            with self.subTest(name):
                self.fake.leak = leak
                self.fails('E-ME-06', self.good(), word)

    def test_06_the_kakao_id_is_unique_and_never_the_student_number_the_response_carries(self):
        # 계정 공장은 학번과 카톡 아이디를 같은 `e2e{n}` 으로 넣고, 서버 응답은 학번을 싣는다 — 공장 값을 그대로 찾으면 거짓 FAIL 이다.
        seen = []
        for _ in range(2):
            self.passes('E-ME-06', self.good())
            seen.append((self.fake.private('id-1')['kakao_id'], self.profile()['student_number']))
        for kakao, student in seen:
            self.assertRegex(kakao, r'^kk[0-9a-f]{8}$')
            self.assertRegex(student, r'^e2e\d+$')  # 공장이 넣은 학번 — 응답에 실린다
            self.assertNotIn(student, kakao)
            self.assertNotIn(kakao, student)
        self.assertNotEqual(seen[0][0], seen[1][0])  # 계정마다 다르다

    def test_06_is_blocked_when_the_private_values_could_not_be_replaced(self):
        self.swallow('PATCH', r'/rest/v1/profile_private')
        self.blocked('E-ME-06', self.good(), '준비', 'real_name')  # 둘 다 못 바꿈 — 실명이 비어 있다
        self.fake.handlers.pop(0)

        def only_the_name(sent):  # 실명만 들어가고 카톡 아이디는 공장 값(`e2e{n}`) 그대로 — 학번과 겹친다
            self.fake.private('id-1')['real_name'] = sent['body']['real_name']
            return Reply(204, None)
        self.fake.handlers.insert(0, ('PATCH', re.compile(r'/rest/v1/profile_private'), only_the_name))
        self.blocked('E-ME-06', self.good(), '준비', '넣은 값과 다르다')

    def test_06_fails_when_the_api_does_not_answer_200(self):
        self.fail_next('GET', r'/me/card-preview')
        self.fails('E-ME-06', self.good(), '/me/card-preview')

    def test_06_fails_when_the_screen_shows_what_must_not_be_there(self):
        for key, word in (('card', '15-4 카드'), ('photos', '실사진 슬라이더'), ('kakao', '카카오'), ('trust', '신뢰 확인 완료'),
                          ('report', '신고하기'), ('block', '차단하기')):
            with self.subTest(key):
                self.fails('E-ME-06', self.good(**{key: key != 'card'}), word)

    def test_06_is_blocked_when_the_phone_or_the_photos_were_never_filled(self):
        self.fake.no_phone = True
        self.blocked('E-ME-06', self.good(), '준비', 'phone_number')
        self.fake.no_phone = False
        self.fake.handlers.insert(0, ('POST', re.compile(r'/profile-onboarding/photos'), Reply(200, {})))
        self.blocked('E-ME-06', self.good(), '준비', '실사진')


class ManageScreenTest(ReadBase):
    def good(self, **over):
        def answer(job):
            row = self.profile()
            return said(**{'sections': list(SECTIONS), 'photos': 3, 'badge': True, 'photo_note': True,
                           'facts': {'내 키': f"{row['height_cm']}cm", 'MBTI': row['mbti'], '학과': row['major']}, **over})
        return answer

    def test_08_sections_in_order_three_photos_badge_note_and_the_facts(self):
        _, app = self.passes('E-ME-08', self.good())
        self.assertEqual(app.jobs, [{'token_hash': 'h'}])
        row = self.profile()
        self.assertEqual((row['height_cm'], row['mbti']), (178, 'ENFP'))
        photos = sorted(self.rows('profile_photos', profile_id='id-1'), key=lambda r: r['position'])
        self.assertEqual([p['position'] for p in photos], [0, 1, 2])

    def test_08_fails_on_a_wrong_order_photo_count_badge_note_or_a_fact(self):
        row_facts = lambda **kw: {'내 키': '178cm', 'MBTI': 'ENFP', '학과': '컴퓨터공학과', **kw}
        for over, word in (({'sections': SECTIONS[::-1]}, '섹션 순서'), ({'sections': SECTIONS[:3]}, '섹션 순서'),
                           ({'photos': 2}, '실사진'), ({'badge': False}, '수락 후 공개'),
                           ({'photo_note': False}, '서로 수락하면'), ({'facts': row_facts(**{'내 키': '170cm'})}, '기본 정보 행'),
                           ({'facts': row_facts(MBTI='선택 안 함')}, '기본 정보 행'), ({'facts': row_facts(학과='-')}, '기본 정보 행')):
            with self.subTest(over):
                self.fails('E-ME-08', self.good(**over), word)

    def test_08_is_blocked_when_a_photo_file_or_row_cannot_be_added_or_was_dropped(self):
        self.fail_next('POST', r'/storage/v1/object/profile-photos/.*')
        self.blocked('E-ME-08', self.good(), '사진 파일 올리기')
        self.fake.handlers.pop(0)
        self.fail_next('POST', r'/rest/v1/profile_photos')
        self.blocked('E-ME-08', self.good(), 'profile_photos 넣기')
        self.fake.handlers.pop(0)
        self.swallow('POST', r'/rest/v1/profile_photos')
        self.blocked('E-ME-08', self.good(), '준비', '사진 2장')

    def test_08_is_blocked_when_there_are_already_more_photos_than_wanted(self):
        # 계정 공장이 사진을 넉 장 넣어 주는 세상 — 셋으로 "줄이는" 일은 안 한다
        both = lambda sent: (self.fake._photo(sent), self.fake._photo(sent))[1]
        self.fake.handlers.insert(0, ('POST', re.compile(r'/profile-onboarding/photos'), both))
        self.blocked('E-ME-08', self.good(), '준비', '이미 4장')

    def test_08_writes_only_to_the_account_it_made(self):
        self.passes('E-ME-08', self.good())
        self.writes_only_mine()


class PreferenceTextTest(ReadBase):
    def answers(self, first=None, second=None):
        ends = {'age_note': f'22세{EN_DASH}35세 이상', 'height_note': '150cm 이하 ~ 190cm 이상'}
        anything = {'age_note': '상관없어요', 'height_note': '상관없어요'}
        return Sequence(said(**{**ends, **(first or {})}), said(**{**anything, **(second or {})}))

    def test_09_end_values_read_over_and_under_and_the_whole_range_reads_anything(self):
        _, app = self.passes('E-ME-09', self.answers())
        self.assertEqual(len(app.jobs), 2)  # 판마다 앱을 한 번씩
        first, second = self.profile(1), self.profile(2)  # 판마다 계정이 새로
        self.assertEqual([first[k] for k in ('preferred_age_min', 'preferred_age_max', 'preferred_height_min', 'preferred_height_max')],
                         [22, 35, 150, 190])
        self.assertEqual([second[k] for k in ('preferred_age_min', 'preferred_age_max', 'preferred_height_min', 'preferred_height_max')],
                         [19, 35, None, None])

    def test_09_fails_in_each_variant_with_its_name(self):
        for first, second, words in (
                ({'age_note': '22세–35세'}, None, ('끝값', '나이 줄')),
                ({'height_note': '150cm ~ 190cm'}, None, ('끝값', '키 줄')),
                ({'age_note': '22세-35세 이상'}, None, ('끝값', '나이 줄')),  # 하이픈 — en dash 가 아니다
                (None, {'age_note': '19세–35세 이상'}, ('전 구간', '나이 줄')),
                (None, {'height_note': '150cm 이하 ~ 190cm 이상'}, ('전 구간', '키 줄'))):
            with self.subTest(first=first, second=second):
                self.fails('E-ME-09', self.answers(first, second), *words)


class LockTest(ReadBase):
    """15-6 닉네임 잠금 — 28(10일 전) · 29(경계 두 판) · 30(한국 날짜). 시계는 [area5_read._now] 로 시험이 쥔다."""

    def setUp(self):
        super().setUp()
        self.skew = timedelta(0)
        patcher = mock.patch.object(area5_read, '_now', lambda: now() + self.skew)
        patcher.start()
        self.addCleanup(patcher.stop)

    def unlock_of(self, n=1):
        at = self.profile(n)['nickname_changed_at']
        return datetime.fromisoformat(at) + timedelta(days=30)

    def good(self, n=1, **over):
        def answer(job):
            unlock = self.unlock_of(n) if self.unlock_of(n) > now() else None
            return said(**{'nickname_enabled': unlock is None, 'height_enabled': True,
                           'unlock_text': unlock_line(unlock) if unlock else None, 'plain_note': unlock is None, **over})
        return answer

    # 28
    def test_28_ten_days_after_the_change_the_field_is_locked_with_the_unlock_day_and_the_height_stays_open(self):
        _, app = self.passes('E-ME-28', self.good())
        self.assertEqual(app.jobs, [{'token_hash': 'h'}])
        gap = now() - datetime.fromisoformat(self.profile()['nickname_changed_at'])
        self.assertAlmostEqual(gap.total_seconds(), 10 * 86400, delta=30)

    def test_28_fails_on_an_open_nickname_field_a_missing_unlock_text_or_a_locked_height(self):
        for over, word in (({'nickname_enabled': True}, '닉네임 칸'), ({'unlock_text': None}, '풀리는 날'),
                           ({'unlock_text': '1월 1일부터 바꿀 수 있어요'}, '풀리는 날'), ({'height_enabled': False}, '키 칸')):
            with self.subTest(over):
                self.fails('E-ME-28', self.good(**over), word)

    def test_28_is_blocked_when_the_server_does_not_lock_or_gives_another_time_or_does_not_answer(self):
        self.fake.ignore_lock = True
        self.blocked('E-ME-28', self.good(), '준비', '풀리는 때')
        self.fake.ignore_lock, self.fake.lock_shift = False, timedelta(hours=1)
        self.blocked('E-ME-28', self.good(), '준비', '풀리는 때')
        self.fake.lock_shift = timedelta(0)
        self.fail_next('GET', r'/me/profile')
        self.blocked('E-ME-28', self.good(), 'GET /me/profile')

    def test_28_writes_only_to_the_account_it_made(self):
        self.passes('E-ME-28', self.good())
        self.writes_only_mine()

    # 29
    def answers_29(self, open_over=None, locked_over=None):
        return Sequence(self.good(1, **(open_over or {})), self.good(2, **(locked_over or {})))

    def test_29_two_minutes_past_the_thirty_days_the_field_is_open_and_two_minutes_short_it_is_locked(self):
        _, app = self.passes('E-ME-29', self.answers_29())
        self.assertEqual(len(app.jobs), 2)
        opened = now() - datetime.fromisoformat(self.profile(1)['nickname_changed_at'])
        short = now() - datetime.fromisoformat(self.profile(2)['nickname_changed_at'])
        self.assertAlmostEqual(opened.total_seconds(), 30 * 86400 + 120, delta=30)
        self.assertAlmostEqual(short.total_seconds(), 30 * 86400 - 120, delta=30)

    def test_29_fails_in_the_wrong_variant(self):
        for open_over, locked_over, words in (({'nickname_enabled': False}, None, ('풀린 쪽', '닉네임 칸')),
                                              ({'unlock_text': '10월 1일부터 바꿀 수 있어요'}, None, ('풀린 쪽', '풀리는 날')),
                                              (None, {'nickname_enabled': True}, ('잠긴 쪽', '닉네임 칸')),
                                              (None, {'unlock_text': None}, ('잠긴 쪽', '풀리는 날'))):
            with self.subTest(open_over=open_over, locked_over=locked_over):
                self.fails('E-ME-29', self.answers_29(open_over, locked_over), *words)

    def test_29_is_blocked_when_the_lock_ran_out_while_the_app_was_reading(self):
        def slow(job):
            self.skew = timedelta(minutes=5)  # 앱이 읽는 사이 5분이 흘렀다 — 2분 남은 잠금이 풀렸을 수 있다
            return self.good(2)(job)
        self.blocked('E-ME-29', Sequence(self.good(1), slow), '풀리는 때', '앱이 읽는 사이')

    # 30
    def test_30_the_unlock_day_is_written_in_korean_time_even_when_utc_is_a_day_earlier(self):
        _, app = self.passes('E-ME-30', self.good())
        unlock = self.unlock_of()
        self.assertEqual((unlock.hour, unlock.minute, unlock.second), (16, 0, 0))  # UTC 16:00 = 한국 다음 날 01:00
        self.assertIn((unlock - now()).days, (19, 20))  # 오늘 + 20일 16:00 UTC — 지금과 사이가 19~20일
        self.assertNotEqual(unlock_line(unlock), f'{unlock.month}월 {unlock.day}일부터 바꿀 수 있어요')

    def test_30_fails_on_the_utc_date_or_none(self):
        def utc_date(job):
            at = datetime.fromisoformat(self.profile()['nickname_changed_at']) + timedelta(days=30)
            return said(nickname_enabled=False, height_enabled=True, unlock_text=f'{at.month}월 {at.day}일부터 바꿀 수 있어요')
        self.fails('E-ME-30', utc_date, 'UTC')
        self.fails('E-ME-30', self.good(unlock_text=None), '풀리는 날')


# ── 탈퇴 ─────────────────────────────────────────────────────────────────────────────────────────────

class WithdrawSheetsTest(ReadBase):
    def first(self, **over):
        return said(**{'title': True, 'lead': True, 'items': list(DELETED), 'warning': True, 'buttons': ['영구 삭제'], **over})

    def final(self, **over):
        return said(**{'final_seen': True, 'final_buttons': ['정말 영구 삭제'], 'closed': True, 'title': '설정', **over})

    def test_wd_01_first_sheet_has_the_title_the_three_lines_the_warning_and_one_button_and_nothing_changes(self):
        _, app = self.passes('E-WD-01', self.first())
        self.assertEqual(app.jobs, [{'token_hash': 'h'}])
        self.assertEqual(self.profile()['status'], 'active')

    def test_wd_01_fails_on_a_missing_title_lead_item_extra_item_warning_or_button(self):
        for over, word in (({'title': False}, '제목'), ({'lead': False}, '안내'), ({'items': DELETED[:2]}, '지워지는 항목'),
                           ({'items': DELETED + ['사진']}, '지워지는 항목'), ({'warning': False}, '경고'),
                           ({'buttons': ['영구 삭제', '취소']}, '버튼'), ({'buttons': []}, '버튼')):
            with self.subTest(over):
                self.fails('E-WD-01', self.first(**over), word)

    def test_wd_01_fails_when_the_app_changed_the_account(self):
        def withdraws(job):
            self.profile().update(status='withdrawn', withdrawn_at=now().isoformat())
            self.fake.rows('signup_blocks').append({'email_hmac': '\\x01', 'blocked_until': 'x'})
            return self.first()
        self.fails('E-WD-01', withdraws, 'status', 'withdrawn_at', 'signup_blocks')

    def test_wd_03_cancel_on_the_final_sheet_closes_it_and_changes_nothing(self):
        _, app = self.passes('E-WD-03', self.final())
        self.assertEqual(app.jobs, [{'token_hash': 'h'}])
        self.assertEqual(self.profile()['status'], 'active')

    def test_wd_03_fails_on_a_missing_final_sheet_wrong_buttons_an_open_sheet_or_a_wrong_screen(self):
        for over, word in (({'final_seen': False}, '최종 시트'), ({'final_buttons': []}, '최종 시트'),
                           ({'closed': False}, '닫힘'), ({'title': '내 프로필'}, '설정')):
            with self.subTest(over):
                self.fails('E-WD-03', self.final(**over), word)

    def test_wd_03_fails_when_the_account_was_withdrawn_or_a_block_row_was_made(self):
        def withdraws(job):
            self.profile().update(status='withdrawn', withdrawn_at=now().isoformat())
            self.fake.rows('signup_blocks').append({'email_hmac': '\\x01', 'blocked_until': 'x'})
            return self.final()
        self.fails('E-WD-03', withdraws, 'status', 'signup_blocks')

    def test_wd_01_03_17_edge_14_read_the_signup_blocks_in_a_fixed_order(self):
        # 행이 천 개를 넘으면 PostgREST 는 잘라 돌려준다 — 순서를 정하지 않으면 앞뒤가 서로 다른 쪽을 읽는다
        for name, answer in (('E-WD-01', self.first()), ('E-WD-03', self.final()), ('E-WD-17', said(buttons=['로그아웃'], withdraw_link=True, sheet=True, warning=True))):
            with self.subTest(name):
                self.fake.sent.clear()
                self.case(name, answer)
                reads = self.fake.by('GET', '/rest/v1/signup_blocks')
                self.assertEqual(len(reads), 2)  # 앞 · 뒤
                self.assertEqual({s['query'].get('order') for s in reads}, {'email_hmac'})

    def test_wd_03_keeps_the_signup_blocks_that_were_already_there(self):
        # 이미 있던 제한 행(다른 사람의 것)은 그대로 있어도 된다 — 앞뒤가 같은지 본다.
        self.fake.handlers.insert(0, ('GET', re.compile(r'/rest/v1/signup_blocks'), Reply(200, [{'email_hmac': '\\xaa'}])))
        self.passes('E-WD-03', self.final())


class SuspendedEntranceTest(ReadBase):
    def good(self, **over):
        return said(**{'buttons': ['로그아웃'], 'withdraw_link': True, 'sheet': True, 'warning': True, **over})

    def test_wd_17_logout_is_the_only_button_but_a_withdraw_text_link_opens_the_suspended_withdraw_sheet(self):
        def answer(job):
            self.assertEqual(self.profile()['status'], 'suspended')  # 앱이 켜지기 전에 이미 정지
            return self.good()
        note, app = self.passes('E-WD-17', answer)
        self.assertEqual(app.jobs, [{'token_hash': 'h'}])
        self.assertIn('시나리오', note)  # 시나리오와 다르다는 것을 메모로 남긴다
        self.assertIn('탈퇴하기', note)
        self.assertEqual(self.profile()['status'], 'suspended')

    def test_wd_17_fails_on_extra_buttons_no_link_no_sheet_no_warning(self):
        for over, word in (({'buttons': ['로그아웃', '탈퇴하기']}, '버튼'), ({'buttons': []}, '버튼'), ({'withdraw_link': False}, '글자 버튼'),
                           ({'sheet': False}, '시트'), ({'warning': False}, '무기한')):
            with self.subTest(over):
                self.fails('E-WD-17', self.good(**over), word)

    def test_wd_17_fails_when_the_app_withdrew_the_suspended_account(self):
        def withdraws(job):
            self.profile().update(status='withdrawn', withdrawn_at=now().isoformat())
            self.fake.rows('signup_blocks').append({'email_hmac': '\\x01', 'blocked_until': 'infinity'})
            return self.good()
        self.fails('E-WD-17', withdraws, 'status', 'signup_blocks')


# ── 시스템 뒤로 · 경계 ────────────────────────────────────────────────────────────────────────────────

def walks(**over):
    """EDGE-13 앱의 말 — 화면마다 열린 화면 · 고친 값 · 포커스 정리 · 뒤로 뒤 도착 화면 · 두 번째 뒤로 뒤 화면(안 보냈으면 None) · 묻는 창.
    [over] 는 {화면 이름: 바꿀 칸}."""
    out = []
    for step, opened, arrival in EDGE_13:
        walk = {'step': step, 'opened': TITLES[opened], 'edited': step in EDITED or None, 'unfocused': step in TYPED,
                'title': TITLES[arrival], 'second_title': None, 'asked': False}
        walk.update(over.get(step, {}))
        out.append(walk)
    return said(walks=out)


class SystemBackTest(ReadBase):
    def edge13(self, answer, steps=STOPS):
        return StepApp(as_fn(answer), steps, self.events)

    def stays(self, step, second, **extra):
        """[step] 에서 첫 뒤로 뒤에도 연 화면 그대로 — 앱이 `{step}-again` 에서 한 번 더 멈추고 두 번째 뒤로 뒤 [second] 를 말한다."""
        steps = list(STOPS)
        steps.insert(steps.index(step) + 1, f'{step}-again')
        opened = {s: o for s, o, _ in EDGE_13}[step]
        return self.edge13(walks(**{step: {'title': TITLES[opened], 'second_title': second, **extra}}), steps)

    def test_edge_13_back_goes_one_screen_up_on_seven_screens_without_a_dialog_and_changes_nothing(self):
        _, app = self.passes('E-EDGE-13', None, self.edge13(walks()))
        self.assertEqual(app.jobs, [{'token_hash': 'h'}])
        self.assertEqual(self.adb_calls, [BACK] * 7)  # 끝 멈춤에서는 뒤로를 안 보낸다
        want = []
        for step, _, _ in EDGE_13:
            want += [f'step:{step}', 'back', 'go']
        self.assertEqual(self.events, want + ['step:end', 'go'])  # 앱이 멈춘 다음에 뒤로, 그다음에 go — 끝 멈춤은 go 만

    def test_edge_13_a_screen_left_only_by_a_second_back_is_a_fail_that_says_the_field_may_have_taken_the_first(self):
        note = self.fails('E-EDGE-13', None, "15c: 뒤로 뒤 앱바 '자기소개·태그 수정'(기대 '프로필 편집')", '첫 뒤로가 먹지 않고 두 번째에 나갔다',
                          '입력칸/키보드가 첫 뒤로를 받았을 가능성', app=self.stays('15c', TITLES['15-5'], unfocused=False))
        self.assertNotIn('멈춘 화면', note)
        self.assertEqual(self.adb_calls, [BACK] * 8)  # 15c 에서만 두 번
        self.assertEqual(self.events[6:12], ['step:15c', 'back', 'go', 'step:15c-again', 'back', 'go'])

    def test_edge_13_after_the_focus_was_cleared_a_second_back_exit_is_not_put_down_to_the_keyboard(self):
        note = self.fails('E-EDGE-13', None, '15-6: 뒤로 뒤 앱바', '첫 뒤로가 먹지 않고 두 번째에 나갔다', '포커스를 정리한 뒤',
                          app=self.stays('15-6', TITLES['15-5']))  # 15-6 은 글자를 넣은 화면 — 앱이 포커스를 풀었다고 말한다
        self.assertNotIn('입력칸/키보드가 첫 뒤로를 받았을 가능성', note)

    def test_edge_13_a_screen_that_stays_after_both_backs_says_so(self):
        note = self.fails('E-EDGE-13', None, '06-1 편집', '뒤로가 두 번 다 먹지 않았다', app=self.stays('06-1', TITLES['06-1']))
        self.assertNotIn('두 번째에 나갔다', note)

    def test_edge_13_a_second_back_that_lands_elsewhere_names_that_screen(self):
        note = self.fails('E-EDGE-13', None, '태그 편집(관심사)', "두 번째 뒤로 뒤 앱바 '내 프로필'", app=self.stays('tag', TITLES['15']))
        self.assertNotIn('두 번 다', note)

    def test_edge_13_the_second_title_is_none_when_no_second_back_was_sent(self):
        self.fails('E-EDGE-13', None, '15-4', '두 번째', app=self.edge13(walks(**{'15-4': {'second_title': TITLES['15']}})))
        silent = walks()
        del silent['walks'][1]['second_title']  # 앱이 키를 말하지 않음 — None(안 보냄)과 가른다
        self.fails('E-EDGE-13', None, '15-4', "'?'", app=self.edge13(silent))

    def test_edge_13_a_second_stop_out_of_place_or_for_an_unknown_screen_is_a_wrong_stop_order(self):
        for steps in (['15-5', '15-4', '15c', '06-1', '15c-again', 'tag', '15-6', '15-7', 'end'],
                      ['15-5', '15-4', 'zz-again', '15c', '06-1', 'tag', '15-6', '15-7', 'end'],
                      ['15-5', '15-4', '15c', '15c-again', '15c-again', '06-1', 'tag', '15-6', '15-7', 'end']):
            with self.subTest(steps):
                self.fails('E-EDGE-13', None, '멈춘 화면', app=self.edge13(walks(), steps))

    def test_edge_13_is_blocked_when_the_app_ends_without_the_end_stop(self):
        # 끝 멈춤이 없는 앱(옛 빌드) — PC 는 다음 멈춤을 기다리다 결과를 받는다
        self.blocked('E-EDGE-13', None, '멈춤', 'end', app=self.edge13(walks(), STOPS[:-1]))
        self.assertEqual(self.adb_calls, [BACK] * 7)

    def test_edge_13_fails_on_a_wrong_arrival_a_wrong_opened_screen_a_dialog_or_a_value_that_was_not_edited(self):
        for over, word in (({'15-6': {'title': TITLES['15']}}, '15-6'), ({'tag': {'title': TITLES['15-5']}}, '관심사'),
                           ({'15-4': {'opened': TITLES['15']}}, '15-4'), ({'15c': {'asked': True}}, '묻는 창'),
                           ({'15c': {'edited': None}}, '고친'), ({'06-1': {'edited': False}}, '고친'), ({'tag': {'edited': False}}, '고친'),
                           ({'15-6': {'edited': None}}, '고친'), ({'15-7': {'edited': None}}, '고친')):
            with self.subTest(over):
                self.fails('E-EDGE-13', None, word, app=self.edge13(walks(**over)))

    def test_edge_13_fails_when_any_one_saved_column_changed(self):
        # 가짜 서버는 요청한 칸만 돌려준다 — 모듈의 SAVED 에서 칸이 빠지면 그 칸의 판은 여기서 통과해 버려 잡힌다.
        for column in SAVED_COLUMNS:
            with self.subTest(column):
                def saves(job, column=column):
                    row = self.profile()
                    row[column] = [row[column], '저장돼 버림']
                    return walks()
                self.fails('E-EDGE-13', None, 'DB', app=self.edge13(saves))

    def test_edge_13_fails_when_a_photo_or_avatar_row_changed(self):
        def adds_a_photo(job):
            self.fake.rows('profile_photos').append({'id': 'z', 'profile_id': 'id-1', 'position': 3, 'storage_path': 'p', 'is_avatar_source': False})
            return walks()

        def adds_an_avatar(job):
            self.fake.rows('profile_avatars').append({'id': 'z', 'profile_id': 'id-1', 'status': 'pending', 'storage_path': 'a'})
            return walks()
        for answer in (adds_a_photo, adds_an_avatar):
            self.fails('E-EDGE-13', None, 'DB', app=self.edge13(answer))

    def test_edge_13_does_not_ask_for_an_edit_on_the_two_screens_without_a_value(self):
        # 15-5 · 15-4 에는 고칠 값이 없다 — edited 가 None 이어도 그 둘은 통과해야 한다(시나리오와 다른 점은 메모에 적는다)
        note, _ = self.passes('E-EDGE-13', None, self.edge13(walks()))
        self.assertIn('15-5', note)

    def test_edge_13_fails_when_the_app_stopped_on_other_screens_or_the_db_changed(self):
        steps = list(STOPS)
        steps[0], steps[1] = steps[1], steps[0]  # 앱이 15-4 를 먼저 열었다 — 시험이 정한 차례가 아니다
        self.fails('E-EDGE-13', None, '멈춘 화면', app=StepApp(as_fn(walks()), steps, self.events))

        def saves(job):
            self.profile()['bio'] = '저장돼 버린 글'
            return walks()
        self.fails('E-EDGE-13', None, 'DB', app=self.edge13(saves))

    def test_edge_13_fails_when_the_app_says_nothing_about_the_screens(self):
        self.fails('E-EDGE-13', None, '15-5', '15-7', app=self.edge13(said(walks=[])))

    def test_edge_13_is_blocked_when_the_app_ends_before_the_last_screen(self):
        short = StepApp(as_fn(walks()), [s for s, _, _ in EDGE_13][:6], self.events)
        self.blocked('E-EDGE-13', None, '멈춤', app=short)

    def test_edge_13_a_silent_app_is_a_fail(self):
        self.fails('E-EDGE-13', None, app=self.edge13(lambda job: None))

    # 14
    def sheets(self, **over):
        out = {'regen': {'step': 'regen', 'open_before': True, 'open_after': False, 'title': TITLES['15']},
               'withdraw-first': {'step': 'withdraw-first', 'open_before': True, 'open_after': False, 'title': TITLES['16'],
                                  'final_open': False},
               'withdraw-final': {'step': 'withdraw-final', 'open_before': True, 'open_after': False, 'title': TITLES['16'],
                                  'first_open': False}}
        for step, fields in over.items():
            out[step] = {**out[step], **fields}
        return said(sheets=list(out.values()))

    def edge14(self, answer):
        return StepApp(as_fn(answer), ['regen', 'withdraw-first', 'withdraw-final'], self.events)

    def test_edge_14_back_closes_only_the_sheet_on_15b_and_both_16c_sheets_and_nothing_is_sent(self):
        _, app = self.passes('E-EDGE-14', None, self.edge14(self.sheets()))
        self.assertEqual(self.adb_calls, [BACK] * 3)
        self.assertEqual(self.events, ['step:regen', 'back', 'go', 'step:withdraw-first', 'back', 'go',
                                       'step:withdraw-final', 'back', 'go'])
        self.assertEqual(self.profile()['status'], 'active')
        self.assertEqual(len(self.rows('profile_avatars')), 1)

    def test_edge_14_fails_on_a_sheet_that_stays_a_wrong_screen_or_the_other_sheet_opening(self):
        for over, word in (({'regen': {'open_after': True}}, '15b'), ({'regen': {'open_before': False}}, '15b'),
                           ({'regen': {'title': TITLES['16']}}, '15b'),
                           ({'withdraw-first': {'open_after': True}}, '16c 1차'), ({'withdraw-first': {'final_open': True}}, '16c 1차'),
                           ({'withdraw-first': {'title': TITLES['15']}}, '16c 1차'),
                           ({'withdraw-final': {'open_after': True}}, '16c 최종'), ({'withdraw-final': {'first_open': True}}, '16c 최종'),
                           ({'withdraw-final': {'title': TITLES['15']}}, '16c 최종')):
            with self.subTest(over):
                self.fails('E-EDGE-14', None, word, app=self.edge14(self.sheets(**over)))

    def test_edge_14_fails_when_the_app_stopped_on_other_sheets(self):
        steps = ['withdraw-first', 'regen', 'withdraw-final']  # 15b 보다 16c 를 먼저 열었다
        self.fails('E-EDGE-14', None, '멈춘 시트', app=StepApp(as_fn(self.sheets()), steps, self.events))

    def test_edge_14_fails_when_a_request_changed_the_account_or_the_avatars(self):
        def regenerates(job):
            self.fake.rows('profile_avatars').append({'id': 'x', 'profile_id': 'id-1', 'status': 'pending', 'storage_path': 'p'})
            self.profile()['status'] = 'withdrawn'
            return self.sheets()
        self.fails('E-EDGE-14', None, '아바타', 'status', app=self.edge14(regenerates))

    # 16
    def edge16(self, answer, top=OURS):
        return StepApp(as_fn(answer), ['back'], self.events, top)

    def test_edge_16_back_on_the_consent_gate_does_nothing_and_the_app_stays_in_front(self):
        _, app = self.passes('E-EDGE-16', said(on_consent=True), self.edge16(said(on_consent=True)))
        self.assertEqual(self.adb_calls, [BACK])
        self.assertEqual(self.events, ['step:back', 'back', 'top', 'go'])  # 뒤로를 보낸 뒤 맨 앞 화면을 본다
        self.assertFalse(any(s['path'] == '/me/consents' for s in self.fake.sent))  # 앱 대신 PC 도 동의를 넣지 않는다

    def test_edge_16_uses_an_account_that_has_not_consented_yet(self):
        self.passes('E-EDGE-16', None, self.edge16(said(on_consent=True)))
        paths = [s['path'] for s in self.fake.sent]
        self.assertIn('/auth/v1/admin/generate_link', paths)
        self.assertNotIn('/me/consents', paths)  # 동의 전 계정이다

    def test_edge_16_fails_when_the_app_left_the_front_or_the_gate_screen_or_a_consent_was_saved(self):
        self.fails('E-EDGE-16', None, '맨 앞', app=self.edge16(said(on_consent=True), LAUNCHER))
        self.fails('E-EDGE-16', None, '02-c', app=self.edge16(said(on_consent=False)))
        consented = []
        self.fake.handlers.insert(0, ('GET', re.compile(r'/rest/v1/user_consents'),
                                      lambda sent: Reply(200, [{'profile_id': 'id-1', 'kind': 'terms'}] if consented else [])))

        def agrees(job):
            consented.append(True)
            return said(on_consent=True)
        self.fails('E-EDGE-16', None, '동의 행', app=self.edge16(agrees))

    def test_edge_16_is_blocked_when_the_account_already_has_a_consent_row(self):
        self.fake.handlers.insert(0, ('GET', re.compile(r'/rest/v1/user_consents'), Reply(200, [{'profile_id': 'id-1', 'kind': 'terms'}])))
        self.blocked('E-EDGE-16', None, '준비', '동의 행', app=self.edge16(said(on_consent=True)))

    # 23
    def good23(self, **over):
        return said(**{'before': '프로필 편집', 'stacked': 1, 'on_profile': True, 'manage_again': False, 'title': '내 프로필', **over})

    def test_edge_23_records_one_layer_when_back_returns_to_15(self):
        note, app = self.passes('E-EDGE-23', self.good23())
        self.assertEqual(app.jobs, [{'token_hash': 'h'}])
        self.assertIn('1겹', note)

    def test_edge_23_records_two_layers_when_15_5_comes_again(self):
        note, _ = self.passes('E-EDGE-23', self.good23(stacked=2, on_profile=False, manage_again=True, title='프로필 편집'))
        self.assertIn('2겹', note)

    def test_edge_23_fails_when_neither_15_nor_15_5_shows_after_back(self):
        self.fails('E-EDGE-23', self.good23(on_profile=False, manage_again=False, title='설정'), '도착')

    def test_edge_23_is_blocked_when_the_second_tap_landed_on_another_screen(self):
        self.blocked('E-EDGE-23', self.good23(before='이상형 조건 수정'), '두 번째 누름', '이상형 조건 수정')


class FakeShapeTest(ReadBase):
    """가짜 서버가 진짜 서버와 같은 모양인지 — 가짜가 칸을 빠뜨리면(학번처럼) 시험이 진짜 서버의 거짓 FAIL 을 못 본다."""

    def test_the_fake_answers_have_the_keys_of_the_real_server(self):
        self.fake.profile('id-1')
        mine = self.fake._me_profile({'auth': 'tok-1'}).body
        self.assertEqual(sorted(mine), sorted(server_keys('me/router.py', 'get_my_profile')))
        shown = self.fake._preview({'auth': 'tok-1'}).body
        self.assertEqual(sorted(shown), sorted(server_keys('cards/router.py', 'profile_detail')))
        self.assertEqual(sorted(shown['profile']), sorted(server_keys('cards/router.py', '_card_profile')))

    def test_the_card_preview_carries_the_student_number_the_factory_saved(self):
        self.fake.profile('id-1').update(student_number='e2e1001')
        self.assertEqual(self.fake._preview({'auth': 'tok-1'}).body['student_number'], 'e2e1001')

    def test_a_get_returns_only_the_selected_columns_in_the_asked_order(self):
        self.fake.rows('signup_blocks').extend([{'email_hmac': 'bb', 'blocked_until': 'x'}, {'email_hmac': 'aa', 'blocked_until': 'y'}])
        url = 'https://sb.test/rest/v1/signup_blocks?select=email_hmac'
        self.assertEqual(tools.call('GET', url, {}).body, [{'email_hmac': 'bb'}, {'email_hmac': 'aa'}])  # 순서 없음 = 넣은 순서
        self.assertEqual(tools.call('GET', url + '&order=email_hmac', {}).body, [{'email_hmac': 'aa'}, {'email_hmac': 'bb'}])
        self.assertEqual(tools.call('GET', url + '&order=email_hmac.desc', {}).body, [{'email_hmac': 'bb'}, {'email_hmac': 'aa'}])
        self.assertEqual(tools.call('GET', url + ',nothing_here', {}).body[0], {'email_hmac': 'bb', 'nothing_here': None})

    def test_an_embedded_column_keeps_its_name(self):
        self.fake.profile('id-1')
        got = tools.call('GET', 'https://sb.test/rest/v1/profiles?id=eq.id-1&select=nickname,universities(name),major', {}).body
        self.assertEqual(sorted(got[0]), ['major', 'nickname', 'universities'])


class AppAnswerTest(ReadBase):
    """한 번 켜서 한 번 말하는 13개 — 앱의 pass 는 판정으로, blocked 는 blocked, 말이 없으면 fail."""

    ONE_SHOT = [c for c in BUNDLE if c not in ('E-EDGE-13', 'E-EDGE-14', 'E-EDGE-16')]

    def test_a_blocked_app_is_blocked_and_a_silent_or_failed_app_is_a_fail(self):
        for case in self.ONE_SHOT:
            with self.subTest(case):
                self.blocked(case, {'result': 'blocked', 'note': '못 찾음'}, '못 찾음')
                self.fails(case, lambda job: None, '답하지 않음')
                self.fails(case, {'result': 'fail', 'note': '앱이 본 것과 다름'}, '앱이 본 것과 다름')

    def test_a_stepping_app_that_is_blocked_is_blocked(self):
        for case, steps in (('E-EDGE-13', STOPS), ('E-EDGE-14', ['regen', 'withdraw-first', 'withdraw-final']),
                            ('E-EDGE-16', ['back'])):
            with self.subTest(case):
                self.blocked(case, {'result': 'blocked', 'note': '못 찾음'}, '못 찾음', app=StepApp(as_fn({'result': 'blocked', 'note': '못 찾음'}), steps, self.events))


def dart_block(text, start, end):
    """[start] 부터 그 뒤 첫 [end] 앞까지 — 함수 하나 · 가설 하나의 몸통."""
    begin = text.index(start)
    return text[begin:text.index(end, begin)]


class AppContractTest(unittest.TestCase):
    """EDGE-13 · ME-08 의 앱 쪽(area5_read.dart)이 PC 쪽과 맞물리는지 — dart 는 여기서 돌릴 수 없어 글자로 맞댄다."""

    def setUp(self):
        self.app = (tools.ROOT / 'frontend' / 'integration_test' / 'area5_read.dart').read_text(encoding='utf-8')
        self.back_from = dart_block(self.app, '_backFrom(WidgetTester', '\n}\n')

    def test_the_walk_keys_the_pc_reads_are_exactly_the_keys_the_app_says(self):
        said_keys = set(re.findall(r"'(\w+)':", self.back_from))
        tree = ast.parse(Path(area5_read.__file__).read_text(encoding='utf-8'))
        read = {node.args[0].value for node in ast.walk(tree)
                if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == 'get'
                and isinstance(node.func.value, ast.Name) and node.func.value.id in ('walk', 'w')
                and node.args and isinstance(node.args[0], ast.Constant)}
        self.assertLessEqual({'second_title', 'unfocused'}, said_keys)
        self.assertEqual(sorted(read), sorted(said_keys))

    def test_a_screen_that_stays_stops_again_and_the_walk_ends_on_the_stop_the_pc_waits_for(self):
        # 두 번째 멈춤은 첫 뒤로 뒤에도 연 화면 그대로일 때만 — 늘 멈추면 PC 가 화면마다 두 번 뒤로를 보내 한 칸 더 올라간다
        self.assertRegex(self.back_from, r"if \(\w+ == opened\) \{\s*await step\('\$name-again'\);")
        self.assertEqual(re.findall(r"\bstep\('\$name(-\w+)'\)", self.back_from), ['-again'])
        self.assertEqual(area5_read.AGAIN, '-again')
        self.assertEqual(re.findall(r"\bstep\('(\w+)'\)", dart_block(self.app, "'E-EDGE-13':", "'E-EDGE-14':")), ['end'])
        self.assertEqual(area5_read.END, 'end')
        # 묻는 창은 두 번째 뒤로가 닫기 전에 본다
        self.assertLess(self.back_from.index('_asking()'), self.back_from.index("step('$name-again')"))

    def test_only_the_two_screens_with_typed_text_clear_the_focus_before_back(self):
        typed = re.findall(r"_backFrom\(tester, '([\w-]+)'[^;]*\btyped: true", self.app)
        self.assertEqual(sorted(typed), ['15-6', '15c'])
        unfocus = self.back_from.index('FocusManager.instance.primaryFocus?.unfocus()')
        self.assertLess(unfocus, self.back_from.index('await step(name)'))
        # 이 바인딩은 진짜 키보드를 쓴다(integration_test registerTestTextInput false) — testTextInput.hide() 는 assert 로 죽는다
        self.assertNotIn('testTextInput', '\n'.join(re.sub(r'//.*$', '', line) for line in self.app.split('\n')))

    def test_08_reads_each_header_where_it_sits_in_the_list_not_where_it_is_on_screen(self):
        # 화면 y + 스크롤 값은 scrollUntilVisible 이 끝에 그리기 없이 스크롤을 옮겨(ensureVisible) 서로 다른 때를 가리킬 수 있다
        order = dart_block(self.app, '_sectionOrder(WidgetTester', '\n}\n')
        self.assertIn('getOffsetToReveal', order)
        for stale in ('pixels', 'getTopLeft'):
            self.assertNotIn(stale, order)
        self.assertIn('await _reveal(tester, find.text(title));', order)  # 제목 줄은 보이는 줄만 만들어지니 끌어온 뒤 읽는다


if __name__ == '__main__':
    unittest.main()
