"""영역 5 폰 A · 고쳐 저장하는 15개(E-ME 07 · 18 · 19 · 20 · 21 · 23 · 24 · 25 · 26 · 27 · 31 · 33 · 34 · 35 · 36)의 PC 쪽 시험 —
폰 · 운영 없이 가짜 앱 · 가짜 서버로 돈다. 저장소 루트에서 `python -m unittest e2e.test_area5_act`.

가짜 서버([ActFake])는 area5_read 시험의 [ReadFake] 에 이 묶음이 쓰는 서버 규칙 — `PATCH /me/profile`(me/router.py · me/schemas.py) ·
`POST /profile-onboarding/ideal-conditions` · `…/interests` · 벡터 행(profile_vectors)과 임베딩 호출 · 닉네임 대소문자 무시 검색 — 만 더했다.
가짜 앱은 test_area3_phone.py 의 App(한 번 켜서 한 번 말함) · MidwayApp(한 번 멈춤)이고, "앱이 눌렀다" 는 시험이 가짜 앱 안에서 같은 서버 API 를
불러(`self.api`) 흉내 낸다 — PC 가 DB 를 보고 판정하는 줄이 진짜 서버 규칙 위에서 도는지 보려고. 계정은 id-1 · 토큰 tok-1.
시험의 글자는 모듈에서 가져오지 않고 그대로 적었다 — 모듈의 상수가 틀려도 시험이 잡는다.
"""

import ast
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock

from e2e import area1, area2, area2_phone3, area5_act, area5_read, tools
from e2e.area2_phone3 import _PAID
from e2e.test_area1 import CFG
from e2e.test_area3_phone import App, said
from e2e.test_area3_phone2 import MidwayApp, as_fn
from e2e.test_area3_safe import _who
from e2e.test_area5_read import ReadBase, ReadFake, delete_button_violations, server_keys
from e2e.tools import Reply, Run

REAL_GUARD = area2._guard  # ActBase 가 가드를 끄기 전의 진짜 가드

BUNDLE = ['E-ME-07', 'E-ME-18', 'E-ME-19', 'E-ME-20', 'E-ME-21', 'E-ME-23', 'E-ME-24', 'E-ME-25', 'E-ME-26', 'E-ME-27',
          'E-ME-31', 'E-ME-33', 'E-ME-34', 'E-ME-35', 'E-ME-36']
PAID = ['E-ME-07', 'E-ME-18', 'E-ME-24', 'E-ME-25']  # 앱이 bio · 이상형 조건을 저장해 서버가 임베딩(OpenAI)을 부르는 넷
OLD_BIO = '주말엔 카페에서 책을 읽어요.'  # 계정 공장의 자기소개(tools.py _step 'bio')
TITLES = {'15': '내 프로필', '15-5': '프로필 편집', '15c': '자기소개·태그 수정', '06-1': '이상형 조건 수정', '15-6': '기본 정보 수정',
          'tag': '관심사 수정'}
INVALID = '입력한 값을 다시 확인해 주세요'
SOON = '닉네임은 30일에 한 번 바꿀 수 있어요'
TAKEN = '이미 있는 닉네임이에요'
NICK = re.compile(r'^[가-힣a-zA-Z]{2,5}$')
ERROR_COLOR = 0xFFC13515  # frontend/lib/core/theme/app_colors.dart AppColors.error
PLANTED = '[1,0,0,0'  # area2._unit(0) 의 앞머리 — 시험이 따로 적는다
NEW_VECTOR = '[0.5,0.5]'
FOUR_ANIMALS = ['dog', 'cat', 'fox', 'bear']
TAG_POOL = tools.ROOT / 'backend' / 'app' / 'profile_onboarding' / 'tags.py'


def now():
    return datetime.now(timezone.utc)


def pool(name):
    """서버 tags.py 의 목록(리터럴)."""
    tree = ast.parse(TAG_POOL.read_text(encoding='utf-8'))
    node = next(n for n in tree.body if isinstance(n, ast.AnnAssign) and n.target.id == name)
    return ast.literal_eval(node.value)


class ActFake(ReadFake):
    """ReadFake + 이 묶음이 부르는 서버 규칙. 응답 칸 · 문구는 진짜 서버 그대로([ServerRulesTest] 가 진짜 스키마와 맞대 본다)."""

    def __init__(self):
        super().__init__()
        self.paid_calls = 0  # 서버가 OpenAI 임베딩을 부른 횟수
        self.embeds = True  # False: bio · 이상형 조건을 저장해도 벡터를 다시 안 만드는 서버
        self.stamp_time = True  # False: 벡터를 바꾸고 updated_at 은 안 건드리는 서버
        self.change_vector = True  # False: updated_at 만 건드리는 서버
        self.clock = timedelta(0)  # DB 시계가 PC 시계보다 이만큼 앞(+) · 뒤(-)
        self.accepts_blank = False  # bio="   " 를 받아 주는 서버
        self.accepts_any_height = False  # 키 범위를 안 보는 서버
        self.accepts_many_types = False  # 얼굴상 · 인상 4개를 받아 주는 서버
        self.stamps_nickname = True  # 닉네임을 바꿀 때 nickname_changed_at 을 적는 서버
        self.always_taken = False  # 어떤 닉네임을 물어도 누가 쓰고 있다고 답하는 서버
        self.taken_names = set()  # 다른 사람이 쓰고 있는 닉네임(소문자)
        self.names = []  # 닉네임 대소문자 무시 검색 요청들
        for method, pattern, handler in (
                ('PATCH', r'/me/profile', self._patch_me), ('POST', r'/profile-onboarding/ideal-conditions', self._ideal),
                ('POST', r'/profile-onboarding/interests', self._interests)):
            self.on(method, pattern, handler)

    # ── 온보딩(계정 공장이 부른다) ──
    def profile(self, pid):
        fresh = pid not in self.profiles
        row = super().profile(pid)
        if fresh:
            # 계정 공장의 값과 일부러 다르게 — PC 가 가설마다 심는 값이 정말 심겼는지(읽어서 다르면 blocked) 시험이 볼 수 있다.
            row.update({'preferred_animal_types': ['fox', 'bear'], 'preferred_impression_types': ['chic', 'tofu'],
                        'preferred_age_min': 20, 'preferred_age_max': 30})
        return row

    def vectors_of(self, who):
        row = next((r for r in self.rows('profile_vectors') if r['profile_id'] == who), None)
        if row is None:  # 진짜 서버는 upsert 다 — 온보딩 어느 단계에서든 행이 생긴다
            row = {'profile_id': who, 'updated_at': now().isoformat(), 'self_embedding': '[0.25,0.25]'}
            self.rows('profile_vectors').append(row)
        return row

    def _basic(self, sent):
        reply = super()._basic(sent)
        # 진짜 서버는 04-1 저장 때 nickname_changed_at 을 now() 로 적는다(profile_onboarding/repository.py:39) — 계정이 처음부터 잠겨 있다.
        self.profile(_who(sent))['nickname_changed_at'] = now().isoformat()
        return reply

    def _bio(self, sent):
        who = _who(sent)
        reply = super()._bio(sent)
        self.profile(who)['bio'] = sent['body']['bio']
        self.vectors_of(who)
        return reply

    # ── 임베딩 ──
    def embed(self, who):
        """refresh_vectors — 벡터 행을 다시 만든다(updated_at 은 DB now())."""
        if not self.embeds:
            return
        self.paid_calls += 1
        row = self.vectors_of(who)
        if self.stamp_time:
            row['updated_at'] = (now() + self.clock).isoformat()
        if self.change_vector:
            row['self_embedding'] = NEW_VECTOR

    # ── PATCH /me/profile ──
    def _patch_me(self, sent):
        """me/router.py update_my_profile + me/schemas.py ProfileUpdateRequest."""
        who, body = _who(sent), sent['body']
        row = self.profile(who)
        if not body:
            return Reply(422, {'detail': [{'msg': 'Value error, 고칠 칸이 없어요'}]})
        if any(value is None for value in body.values()):
            return Reply(422, {'detail': [{'msg': 'Value error, 빈 값으로는 바꿀 수 없어요'}]})
        if 'bio' in body and not body['bio'].strip() and not self.accepts_blank:
            return Reply(422, {'detail': [{'msg': 'Value error, 자기소개를 입력해 주세요'}]})
        if 'nickname' in body and not NICK.fullmatch(body['nickname']):
            return Reply(422, {'detail': [{'msg': "String should match pattern '^[가-힣a-zA-Z]{2,5}$'"}]})
        fields = dict(body)
        if 'bio' in fields:
            fields['bio'] = fields['bio'].strip()
        if 'nickname' in fields:
            if fields['nickname'] == row['nickname']:
                del fields['nickname']
            else:
                at = row['nickname_changed_at']
                if at and datetime.fromisoformat(at) + timedelta(days=30) > now():
                    return Reply(409, {'detail': SOON})
                if any((p.get('nickname') or '').lower() == fields['nickname'].lower() for p in self.profiles.values() if p is not row):
                    return Reply(409, {'detail': TAKEN})
                if self.stamps_nickname:
                    fields['nickname_changed_at'] = (now() + self.clock).isoformat()
        if 'height_cm' in fields and not 120 <= fields['height_cm'] <= 230 and not self.accepts_any_height:
            return Reply(422, {'detail': INVALID})  # DB check profiles_height_range(23514)가 core/http.py 에서 422 로
        row.update(fields)
        if 'bio' in fields:
            self.embed(who)
        return Reply(200, {'ok': True})

    # ── POST /profile-onboarding/ideal-conditions · interests ──
    def _ideal(self, sent):
        who, body = _who(sent), sent['body']
        for key in ('preferred_animal_types', 'preferred_impression_types'):
            size = len(body[key])
            if size > 3 and not self.accepts_many_types:
                return Reply(422, {'detail': [{'msg': f'List should have at most 3 items after validation, not {size}'}]})
            if size < 1:
                return Reply(422, {'detail': [{'msg': 'List should have at least 1 item after validation, not 0'}]})
        self.profile(who).update({**{k: body.get(k) for k in ('preferred_age_min', 'preferred_age_max', 'preferred_height_min',
                                                               'preferred_height_max', 'preferred_animal_types',
                                                               'preferred_impression_types')},
                                  'preferred_mbti_flags': body.get('preferred_mbti_flags', {})})
        self.embed(who)
        return Reply(200, {'ok': True})

    def _interests(self, sent):
        tags = sent['body']['tags']
        if not 3 <= len(tags) <= 5 or len(set(tags)) != len(tags) or set(tags) - set(pool('INTEREST_TAGS')):
            return Reply(422, {'detail': '목록에 없는 태그 · 개수'})
        self.profile(_who(sent))['interest_tags'] = tags
        return Reply(200, {'ok': True})

    # ── 닉네임 대소문자 무시 검색(PostgREST ilike) ──
    def _table(self, method, name, sent):
        nick = sent['query'].get('nickname', '')
        if method == 'GET' and name == 'profiles' and nick.startswith('ilike.'):
            self.names.append(nick[6:])
            if self.always_taken or nick[6:].lower() in self.taken_names:
                return Reply(200, [{'id': 'x'}])
            return Reply(200, [{'id': p['id']} for p in self.profiles.values() if (p.get('nickname') or '').lower() == nick[6:].lower()])
        return super()._table(method, name, sent)


class ActBase(ReadBase):
    """ReadBase 의 도우미(case · passes · fails · blocked · profile · rows · swallow …)를 쓰되 가짜 서버는 [ActFake] 로."""

    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.run_ = Run(self.root / 'area5-act', 'b', cfg={**CFG}, key='svc')
        self.fake = ActFake()
        self.events, self.adb_calls, self.options = [], [], []

        def call(method, url, headers=None, body=None, raw=None, **options):
            self.options.append((method, url, options))
            return self.fake(method, url, headers, body, raw, **options)

        def fake_adb(serial, *args, check=True):
            self.adb_calls.append((serial, *args))
            return ''

        def counting(original):
            def wrapped(app, *args, **kwargs):
                self.fake.paid_calls = 0  # 임베딩 횟수는 앱이 켜진 뒤부터 센다 — 계정 공장의 온보딩도 같은 임베딩을 부른다
                return original(app, *args, **kwargs)
            return wrapped

        for patcher in (mock.patch.object(App, '__call__', counting(App.__call__)),
                        mock.patch.object(MidwayApp, '__call__', counting(MidwayApp.__call__)),
                        mock.patch.object(tools, 'call', call), mock.patch.object(tools, 'adb', fake_adb),
                        mock.patch.object(Run, 'shot'), mock.patch.object(Run, 'remember'), mock.patch.object(area2, '_guard'),
                        mock.patch.object(area2_phone3, '_guard'), mock.patch.dict(os.environ, {'E2E_REAL_AI': '1'})):
            patcher.start()
            self.addCleanup(patcher.stop)
        _PAID.clear()
        self.addCleanup(_PAID.clear)

    def api(self, method, path, body, n=1):
        """가짜 앱이 서버로 보내는 요청 — 진짜 앱처럼 자기 토큰으로."""
        return tools.api(CFG, method, path, f'tok-{n}', body)

    def vectors(self, n=1):
        return next(r for r in self.fake.rows('profile_vectors') if r['profile_id'] == f'id-{n}')

    def reset_paid(self):
        _PAID.clear()


def unlocked(fake, n=1):
    return fake.profile(f'id-{n}')['nickname_changed_at'] is None


# ── 묶음 등록 · 앱 쪽 약속 ───────────────────────────────────────────────────────────────────────────

class RegistryTest(unittest.TestCase):
    def test_bundle_is_the_fifteen_in_the_order_of_the_scenario(self):
        self.assertEqual(area1.BUNDLES['area5-act'], BUNDLE)
        self.assertEqual(list(area5_act.PHONE), BUNDLE)
        self.assertLessEqual(set(BUNDLE), set(area1.PHONE))

    def test_the_runner_sees_the_bundle(self):
        # 새 인터프리터로 — 이 시험 파일이 area5_act 를 먼저 들여오면 진행 프로그램이 안 들여와도 통과해 버린다.
        probe = 'from e2e import __main__ as m, area1; print(m.BUNDLES.get("area5-act"), "E-ME-07" in area1.PHONE)'
        out = subprocess.run([sys.executable, '-c', probe], cwd=tools.ROOT, capture_output=True, text=True, check=True).stdout
        self.assertEqual(out.strip(), f'{BUNDLE} True')

    def test_the_other_c_bundle_is_not_here(self):
        # 사진 · 아바타 8개(12 · 13 · 14 · 38 · 39 · 41 · 42 · 44)는 다음 PR(C2)이다.
        for number in (12, 13, 14, 38, 39, 41, 42, 44):
            self.assertNotIn(f'E-ME-{number}', area5_act.PHONE)


def dart(name):
    return (tools.ROOT / 'frontend' / 'integration_test' / name).read_text(encoding='utf-8')


def lib(*parts):
    return (tools.ROOT / 'frontend' / 'lib' / Path(*parts)).read_text(encoding='utf-8')


class AppContractTest(unittest.TestCase):
    """PC 가 읽는 앱 Map 키와 앱이 만드는 키가 한 글자도 다르지 않은지 — 오타 한 글자는 늘 FAIL 이라 기계로 맞댄다."""

    def test_the_app_registers_the_same_fifteen_cases(self):
        keys = re.findall(r"^\s*'(E-[A-Z]+-\d+)':", dart('area5_act.dart'), re.M)
        self.assertEqual(keys, BUNDLE)

    def test_area5_dart_only_adds_the_part_the_spread_and_the_import_the_new_file_needs(self):
        text = dart('area5.dart')
        self.assertIn("part 'area5_act.dart';", text)
        self.assertIn('...area5CasesAct', text)

    def test_every_key_the_pc_reads_is_a_key_the_app_says(self):
        said_keys = set(re.findall(r"'(\w+)':", dart('area5_act.dart')))
        tree = ast.parse(Path(area5_act.__file__).read_text(encoding='utf-8'))
        read = set()
        for node in ast.walk(tree):
            # 앱의 말을 읽는 변수는 said(맨 위) · probe(닉네임 한 번) · line(키 한 줄) 셋이다 — 이름을 늘리면 여기도 늘린다
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == 'get' \
                    and isinstance(node.func.value, ast.Name) and node.func.value.id in ('said', 'probe', 'line') \
                    and node.args and isinstance(node.args[0], ast.Constant) and isinstance(node.args[0].value, str):
                read.add(node.args[0].value)
            # `for key, want, label in (('title', …), …)` 처럼 튜플 첫 칸에 키를 적고 said.get(key) 로 읽는 줄
            if isinstance(node, ast.For) and isinstance(node.iter, ast.Tuple):
                read |= {e.elts[0].value for e in node.iter.elts if isinstance(e, ast.Tuple) and e.elts
                         and isinstance(e.elts[0], ast.Constant) and isinstance(e.elts[0].value, str)
                         and re.fullmatch(r'[a-z_]+', e.elts[0].value)}
        # 얼굴상 · 인상 한 벌은 f'{prefix}_start' 처럼 이어 붙여 읽는다
        read |= {f'{prefix}_{suffix}' for prefix in ('animal', 'impression') for suffix in ('start', 'zero', 'zero_save', 'three', 'four')}
        self.assertGreater(len(read), 60)  # 읽는 키를 못 찾았다면 이 시험이 빈 껍데기다
        self.assertEqual(sorted(read - said_keys), [])

    def test_every_key_the_app_reads_from_the_job_is_one_the_pc_sends(self):
        wanted = set(re.findall(r"job\['(\w+)'\]", dart('area5_act.dart')))
        tree = ast.parse(Path(area5_act.__file__).read_text(encoding='utf-8'))
        sent = {kw.arg for node in ast.walk(tree) if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                and node.func.id == 'phone' for kw in node.keywords if kw.arg}
        self.assertEqual(sorted(wanted - sent - {'token_hash'}), [])
        self.assertGreater(len(sent), 5)

    def test_the_app_side_has_no_way_to_tap_the_final_delete_button(self):
        # area5_read 의 보호 장치(글자 · 상수 · 형으로 누르기)를 그대로 쓰되, 이 파일에서 `button(…)` 으로 눌러도 되는 라벨은 `_actSave` 하나뿐이다.
        found = [(kind, line) for kind, line in delete_button_violations(dart('area5_act.dart'))
                 if not (kind == 'b2' and set(re.findall(r'\bbutton\(([^()]*)\)', line)) == {'_actSave'})]
        self.assertEqual(found, [])
        # 보호 장치가 이 파일에서도 살아 있다 — 다른 라벨을 누르는 줄을 더하면 걸린다.
        probe = dart('area5_act.dart') + '\nvoid probe() {\n  tap(tester, button(_somethingElse));\n}\n'
        self.assertTrue([1 for kind, line in delete_button_violations(probe) if kind == 'b2' and '_somethingElse' in line])

    def test_the_literals_the_app_looks_for_are_in_the_real_screens(self):
        # 앱 쪽이 찾는 글자(앱바 제목 · 안내 · 라벨 · 오류)가 지금 lib 에 그대로 있다 — 시나리오가 아니라 코드에서 옮긴 글자다.
        screens = '\n'.join(path.read_text(encoding='utf-8') for path in (tools.ROOT / 'frontend' / 'lib').rglob('*.dart'))
        for literal in ('저장', '프로필 편집', '자기소개·태그 수정', '이상형 조건 수정', '기본 정보 수정', '저장했어요', '사용할 수 있는 닉네임이에요',
                        '한글 또는 영문 2~5자로 입력해 주세요', '이미 있는 닉네임이에요', '숫자 3자리를 확인해 주세요', '키는 상관없어요',
                        '나이는 상관없어요', '강아지상', '고양이상', '여우상', '곰상', '토끼상', '아랍상', '두부상', '선한상', '시크상', '청순상',
                        '수정', '선호 나이 범위', '선호 키 범위', '자기소개 · 태그'):
            with self.subTest(literal):
                self.assertIn(f"'{literal}'", screens)
                self.assertIn(f"'{literal}'", dart('area5_act.dart') + dart('area5.dart') + dart('area1.dart'))
        self.assertIn(SOON, (tools.ROOT / 'backend' / 'app' / 'core' / 'errors.py').read_text(encoding='utf-8'))
        self.assertIn(f"'{SOON}'", dart('area5_act.dart'))

    def test_the_error_color_is_the_one_in_the_theme(self):
        self.assertIn(f'Color error = Color(0x{ERROR_COLOR:08X})', lib('core', 'theme', 'app_colors.dart'))

    def test_the_module_reads_the_same_error_color_and_stops_when_it_cannot(self):
        self.assertEqual(area5_act._error_color(), ERROR_COLOR)
        empty = Path(tempfile.mkdtemp())
        (empty / 'frontend' / 'lib' / 'core' / 'theme').mkdir(parents=True)
        (empty / 'frontend' / 'lib' / 'core' / 'theme' / 'app_colors.dart').write_text('class AppColors {}', encoding='utf-8')
        with mock.patch.object(tools, 'ROOT', empty), self.assertRaises(tools.Blocked) as caught:
            area5_act._error_color()
        self.assertIn('AppColors.error', str(caught.exception))

    def test_the_screens_say_the_same_numbers_and_strings(self):
        # 15-6 의 닉네임 칸 아래 오류 · 키 범위 · 디바운스 / 15c 저장 규칙 / 태그 3~5개 — 시험이 기대하는 숫자가 지금 코드의 숫자다.
        basic = lib('me', 'viewmodel', 'basic_info_edit_view_model.dart')
        self.assertIn('Duration(milliseconds: 300)', basic)
        self.assertIn('value >= 120 && value <= 230', basic)
        self.assertIn('bio.trim().isNotEmpty', lib('me', 'viewmodel', 'profile_edit_view_model.dart'))
        kinds = lib('profile', 'viewmodel', 'tag_picker_kind.dart')
        self.assertIn('minCount = 3', kinds)
        self.assertIn('maxCount = 5', kinds)
        self.assertIn('maxAppearanceChoices = 3', lib('profile', 'viewmodel', 'ideal_conditions_ui_state.dart'))
        self.assertIn('RegExp(r\'^[가-힣a-zA-Z]{2,5}$\')', lib('profile', 'viewmodel', 'basic_info_ui_state.dart'))
        self.assertIn('[가-힣a-zA-Zㄱ-ㅎㅏ-ㅣ]', lib('profile', 'view', 'basic_info_screen.dart'))  # 입력칸이 걸러 내는 글자


# ── 서버 규칙: 가짜가 진짜 서버를 따라가는지 ──────────────────────────────────────────────────────────

def backend_models():
    """백엔드 스키마(pydantic)를 들여올 수 있으면 — 진짜 422 규칙을 가짜와 맞대 보는 데 쓴다. 못 들여오면 None(시험은 건너뛴다)."""
    sys.path.insert(0, str(tools.ROOT / 'backend'))
    try:
        from app.me.schemas import ProfileUpdateRequest
        from app.profile_onboarding.schemas import IdealConditionsRequest
    except Exception:  # noqa: BLE001 — pydantic 이 없는 파이썬
        return None
    finally:
        sys.path.pop(0)
    return ProfileUpdateRequest, IdealConditionsRequest


class ServerRulesTest(ActBase):
    def real(self):
        models = backend_models()
        if models is None:
            self.skipTest('백엔드 스키마를 들여올 수 없는 파이썬')
        return models

    def accepted(self, model, **fields):
        try:
            model(**fields)
        except Exception:  # noqa: BLE001
            return False
        return True

    def test_the_blank_bio_is_422_in_the_real_schema_and_in_the_fake(self):
        update, _ = self.real()
        for bio, ok in (('   ', False), ('', False), ('\n\t ', False), ('  글  ', True)):
            with self.subTest(bio):
                self.assertEqual(self.accepted(update, bio=bio), ok)
                self.fake.profile('id-1')
                reply = self.fake._patch_me({'auth': 'tok-1', 'body': {'bio': bio}})
                self.assertEqual(reply[0] == 200, ok)

    def test_the_422_reason_text_is_the_one_the_module_looks_for(self):
        update, _ = self.real()
        with self.assertRaises(Exception) as caught:
            update(bio='   ')
        self.assertIn('자기소개를 입력해 주세요', str(caught.exception))

    def test_four_appearance_types_are_422_in_the_real_schema_and_the_reason_says_at_most_3(self):
        _, ideal = self.real()
        base = {'preferred_age_min': 20, 'preferred_age_max': 30, 'preferred_animal_types': ['dog'], 'preferred_impression_types': ['kind']}
        for key, values, ok in (('preferred_animal_types', FOUR_ANIMALS, False), ('preferred_animal_types', FOUR_ANIMALS[:3], True),
                                ('preferred_impression_types', ['arab', 'tofu', 'kind', 'chic'], False)):
            with self.subTest((key, len(values))):
                self.assertEqual(self.accepted(ideal, **{**base, key: values}), ok)
        with self.assertRaises(Exception) as caught:
            ideal(**{**base, 'preferred_animal_types': FOUR_ANIMALS})
        self.assertIn('at most 3', str(caught.exception))

    def test_a_height_out_of_range_is_the_db_check_and_core_http_turns_it_into_the_invalid_input_422(self):
        migration = (tools.ROOT / 'supabase' / 'migrations' / '20260913054544_create_profiles.sql').read_text(encoding='utf-8')
        self.assertIn('height_cm between 120 and 230', migration)
        http = (tools.ROOT / 'backend' / 'app' / 'core' / 'http.py').read_text(encoding='utf-8')
        self.assertIn('"23514": 422', http)
        self.assertIn('raise HTTPException(status_code=422, detail=errors.INVALID_INPUT)', http)
        self.assertIn(f'INVALID_INPUT = "{INVALID}"', (tools.ROOT / 'backend' / 'app' / 'core' / 'errors.py').read_text(encoding='utf-8'))
        # me/schemas.py 는 키를 따로 안 본다 — 300 이 닿는 곳은 DB 하나다(그래서 서버가 받아들인 뒤 DB 에서 422).
        self.assertNotIn('height_cm: int = Field', (tools.ROOT / 'backend' / 'app' / 'me' / 'schemas.py').read_text(encoding='utf-8'))
        self.fake.profile('id-1')
        self.assertEqual(self.fake._patch_me({'auth': 'tok-1', 'body': {'height_cm': 300}}), Reply(422, {'detail': INVALID}))

    def test_only_a_bio_save_remakes_the_vectors_on_patch_me_and_the_ideal_conditions_do(self):
        # me/router.py:233 `if "bio" in fields` — 닉네임 · 키만 고치면 임베딩을 안 부른다. 이상형 조건 저장은 _refresh_vectors 를 부른다.
        router = (tools.ROOT / 'backend' / 'app' / 'me' / 'router.py').read_text(encoding='utf-8')
        self.assertIn('if "bio" in fields:', router)
        self.assertEqual(len(re.findall(r'refresh_vectors', router.split('async def update_my_profile')[1])), 1)
        onboarding = (tools.ROOT / 'backend' / 'app' / 'profile_onboarding' / 'router.py').read_text(encoding='utf-8')
        ideal = onboarding.split('async def submit_ideal_conditions')[1].split('@router')[0]
        self.assertIn('_refresh_vectors', ideal)
        tags = onboarding.split('async def _submit_tags')[1].split('@router')[0]
        self.assertNotIn('_refresh_vectors', tags)  # 태그 저장은 벡터를 안 부른다(ME-21 은 유료가 아니다)
        self.fake.profile('id-1')
        self.fake.rows('profile_vectors').append({'profile_id': 'id-1', 'updated_at': 'x', 'self_embedding': 'y'})
        self.fake._patch_me({'auth': 'tok-1', 'body': {'height_cm': 180}})
        self.assertEqual(self.fake.paid_calls, 0)
        self.fake._patch_me({'auth': 'tok-1', 'body': {'bio': '글'}})
        self.assertEqual(self.fake.paid_calls, 1)

    def test_the_fake_get_me_profile_still_has_the_keys_of_the_real_server(self):
        self.fake.profile('id-1')
        self.assertEqual(sorted(self.fake._me_profile({'auth': 'tok-1'}).body), sorted(server_keys('me/router.py', 'get_my_profile')))

    def test_the_fake_answers_of_the_three_writes_have_the_keys_of_the_real_server(self):
        self.fake.profile('id-1')
        patched = self.fake._patch_me({'auth': 'tok-1', 'body': {'height_cm': 180}})
        ideal = self.fake._ideal({'auth': 'tok-1', 'body': {'preferred_age_min': 20, 'preferred_age_max': 30, 'preferred_animal_types': ['dog'],
                                                             'preferred_impression_types': ['kind']}})
        tags = self.fake._interests({'auth': 'tok-1', 'body': {'tags': ['카페가기', '자전거', '패션']}})
        for reply, (path, function) in ((patched, ('me/router.py', 'update_my_profile')),
                                        (ideal, ('profile_onboarding/router.py', 'submit_ideal_conditions')),
                                        (tags, ('profile_onboarding/router.py', '_submit_tags'))):
            with self.subTest(function):
                self.assertEqual((reply[0], sorted(reply.body)), (200, sorted(server_keys(path, function))))

    def test_the_fake_error_bodies_have_the_shape_fastapi_gives(self):
        # HTTPException 은 {"detail": 글자}, 스키마 검증 422 는 {"detail": [{"msg": …}, …]} — 모듈의 Check.reply 가 읽는 모양
        self.fake.profile('id-1')['nickname_changed_at'] = now().isoformat()
        self.fake.profile('id-1')['nickname'] = 'Mine'
        soon = self.fake._patch_me({'auth': 'tok-1', 'body': {'nickname': 'Other'}})
        self.assertEqual((soon[0], soon.body), (409, {'detail': SOON}))
        blank = self.fake._patch_me({'auth': 'tok-1', 'body': {'bio': '  '}})
        self.assertEqual(blank[0], 422)
        self.assertIsInstance(blank.body['detail'], list)
        self.assertTrue(all('msg' in item for item in blank.body['detail']))
        self.assertIn('HTTPException(status_code=409, detail=errors.NICKNAME_CHANGE_TOO_SOON)',
                      (tools.ROOT / 'backend' / 'app' / 'me' / 'router.py').read_text(encoding='utf-8'))

    def test_the_tags_the_module_uses_are_in_the_server_pool(self):
        interests = pool('INTEREST_TAGS')
        self.assertEqual(len(interests), 45)
        for tag in area5_act.INTERESTS + [area5_act.EXTRA, area5_act.SIXTH]:
            self.assertIn(tag, interests)
        self.assertEqual(len(set(area5_act.INTERESTS + [area5_act.EXTRA, area5_act.SIXTH])), 6)
        self.assertEqual(len(area5_act.INTERESTS), 4)

    def test_the_fake_nickname_lock_starts_on_every_new_account_like_the_real_onboarding(self):
        repository = (tools.ROOT / 'backend' / 'app' / 'profile_onboarding' / 'repository.py').read_text(encoding='utf-8')
        self.assertIn('"nickname_changed_at": "now()"', repository)


# ── 유료(임베딩) 문 ─────────────────────────────────────────────────────────────────────────────────

class PaidGateTest(ActBase):
    def test_without_the_env_var_the_four_paid_cases_are_blocked_and_not_one_request_goes_out(self):
        for name in PAID:
            with self.subTest(name), mock.patch.dict(os.environ, {}, clear=True):
                self.blocked(name, said(), 'E2E_REAL_AI')
                self.assertEqual(self.fake.sent, [])  # 계정도 만들지 않는다
                self.assertEqual(self.options, [])

    def test_the_other_eleven_do_not_need_the_env_var(self):
        # 키 · 닉네임 · 태그 · 열고 닫기만 하는 가설은 임베딩을 안 부른다 — 환경변수 없이도 돈다(앱이 말을 안 하면 fail 이지 blocked 가 아니다).
        for name in [c for c in BUNDLE if c not in PAID]:
            with self.subTest(name), mock.patch.dict(os.environ, {}, clear=True):
                (result, note), _ = self.case(name, said(), MidwayApp(as_fn(said()), 'opened', self.events) if name == 'E-ME-31' else None)
                self.assertNotIn('E2E_REAL_AI', note)

    def test_a_failed_paid_case_gives_the_same_fail_and_does_not_start_the_app_again(self):
        app = App(as_fn(said(save_title='설정', card_bios=[], old_in_card=True)))
        (first, note), _ = self.case('E-ME-07', None, app)
        self.assertEqual(first, 'fail')
        (second, again), _ = self.case('E-ME-07', None, app)
        self.assertEqual(second, 'fail')
        self.assertIn('유료 호출 뒤라 다시 하지 않음', again)
        self.assertEqual(len(app.jobs), 1)  # 앱을 두 번 켜지 않았다
        self.assertEqual(self.fake.sent, [])  # 계정도 다시 만들지 않았다

    def test_a_blocked_paid_case_is_not_run_again(self):
        app = App(as_fn({'result': 'blocked', 'note': '못 찾음'}))
        (first, _), _ = self.case('E-ME-24', None, app)
        self.assertEqual(first, 'blocked')
        (second, note), _ = self.case('E-ME-24', None, app)
        self.assertEqual(second, 'blocked')
        self.assertIn('재시도 안 함', note)
        self.assertEqual(len(app.jobs), 1)

    def test_a_setup_failure_before_the_app_starts_is_not_marked_as_paid(self):
        self.swallow('PATCH', r'/rest/v1/profile_vectors')
        self.blocked('E-ME-18', said(), '준비')
        self.assertNotIn('E-ME-18', _PAID)  # 비용이 나가기 전의 막힘이라 다음에 다시 돌 수 있다
        self.fake.handlers.pop(0)
        _, app = self.passes('E-ME-18', self.good_18())
        self.assertEqual(len(app.jobs), 1)

    def good_18(self):
        def answer(job):
            new = job['bio'].strip()
            self.api('PATCH', '/me/profile', {'bio': new})
            return said(title='프로필 편집', manage_bios=[new])
        return answer

    def test_a_pass_is_remembered_so_a_second_call_does_not_pay_again(self):
        self.passes('E-ME-18', self.good_18())
        self.assertEqual(_PAID['E-ME-18'][0], 'pass')
        self.assertEqual(self.fake.paid_calls, 1)
        self.fake.paid_calls = 0
        (second, note), _ = self.case('E-ME-18', self.good_18())
        self.assertEqual(second, 'blocked')
        self.assertEqual(self.fake.paid_calls, 0)  # 두 번째는 앱도 서버도 건드리지 않는다


# ── E-ME-07 · 18 자기소개 저장 ──────────────────────────────────────────────────────────────────────

class BioSaveTest(ActBase):
    def good_07(self, **over):
        def answer(job):
            new = job['bio'].strip()
            reply = self.api('PATCH', '/me/profile', {'bio': new})  # 앱은 앞뒤 공백을 자르고 보낸다(profile_edit_view_model.dart save)
            self.assertEqual(reply[0], 200)
            return said(**{'save_title': '프로필 편집', 'card_bios': [new], 'old_in_card': False, **over})
        return answer

    def test_07_the_new_text_shows_on_the_card_after_back_to_15_and_the_old_one_does_not(self):
        _, app = self.passes('E-ME-07', self.good_07())
        job = app.jobs[0]
        self.assertEqual(job['token_hash'], 'h')
        self.assertTrue(job['bio'].startswith('  ') and job['bio'].endswith('  '))  # 앞뒤 공백을 감싸 쳐도 15-4 에는 자른 글
        self.assertIn(job['tag'], job['bio'])
        self.assertRegex(job['tag'], r'^[0-9a-f]{8}$')
        self.assertEqual(job['old'], OLD_BIO)
        self.assertNotIn(job['tag'], OLD_BIO)  # 새 글을 찾는 낱말이 옛 글과 겹치지 않는다
        self.assertEqual(self.profile()['bio'], job['bio'].strip())
        self.assertEqual(self.fake.paid_calls, 1)
        self.assertEqual(len(self.fake.by('PATCH', '/me/profile')), 1)  # 서버 쓰기는 앱 한 번뿐 — PC 는 쓰지 않는다

    def test_07_the_tag_is_new_every_time(self):
        tags = []
        for _ in range(2):
            self.reset_paid()
            _, app = self.passes('E-ME-07', self.good_07())
            tags.append(app.jobs[0]['tag'])
        self.assertNotEqual(*tags)

    def test_07_fails_on_a_card_that_shows_the_old_text_nothing_the_old_text_beside_it_or_a_wrong_screen_after_the_save(self):
        for over, word in (({'card_bios': [OLD_BIO]}, '15-4 자기소개'), ({'card_bios': []}, '15-4 자기소개'),
                           ({'card_bios': ['x', 'y']}, '15-4 자기소개'), ({'old_in_card': True}, '옛 글'),
                           ({'save_title': '설정'}, '15-5')):
            with self.subTest(over):
                self.reset_paid()
                self.fails('E-ME-07', self.good_07(**over), word)

    def test_07_fails_when_the_text_was_not_saved_or_saved_with_the_spaces(self):
        self.fails('E-ME-07', lambda job: said(save_title='프로필 편집', card_bios=[job['bio'].strip()], old_in_card=False), 'DB 자기소개')
        self.reset_paid()

        def raw(job):
            self.profile()['bio'] = job['bio']
            return said(save_title='프로필 편집', card_bios=[job['bio'].strip()], old_in_card=False)
        self.fails('E-ME-07', raw, 'DB 자기소개')

    def test_07_fails_when_the_app_says_nothing(self):
        self.fails('E-ME-07', lambda job: None, '답하지 않음')

    def test_07_is_blocked_when_the_first_bio_is_empty(self):
        # 처음 글이 비어 있으면 "옛 글이 안 보인다" 가 증거가 못 된다
        def empty(sent):
            reply = self.fake._bio(sent)
            self.fake.profile(_who(sent))['bio'] = ''
            return reply
        self.fake.handlers.insert(0, ('POST', re.compile(r'/profile-onboarding/bio'), empty))
        self.blocked('E-ME-07', said(), '준비', '자기소개가 비어')
        self.assertNotIn('E-ME-07', _PAID)

    # 18
    def good_18(self, **over):
        def answer(job):
            planted = self.vectors()
            assert PLANTED in planted['self_embedding'], planted  # 앱이 켜지기 전에 심어 둔 값
            assert now() - datetime.fromisoformat(planted['updated_at']) > timedelta(hours=23), planted
            new = job['bio'].strip()
            self.api('PATCH', '/me/profile', {'bio': new})
            return said(**{'title': '프로필 편집', 'manage_bios': [new], **over})
        return answer

    def test_18_saving_the_bio_returns_to_15_5_trims_the_text_and_remakes_the_vector_row(self):
        note, app = self.passes('E-ME-18', self.good_18())
        job = app.jobs[0]
        self.assertTrue(job['bio'].startswith('  '))
        self.assertEqual(self.profile()['bio'], job['bio'].strip())
        row = self.vectors()
        self.assertEqual(row['self_embedding'], NEW_VECTOR)
        self.assertGreater(datetime.fromisoformat(row['updated_at']), now() - timedelta(minutes=1))
        self.assertIn('하루 전', note)  # 시계 대신 심어 둔 값과 견줬다는 것을 메모로 남긴다
        self.assertEqual(self.fake.paid_calls, 1)

    def test_18_fails_on_a_wrong_screen_or_a_text_that_is_not_on_15_5(self):
        for over, word in (({'title': '자기소개·태그 수정'}, '15-5'), ({'manage_bios': []}, '15-5 자기소개'), ({'manage_bios': [OLD_BIO]}, '15-5 자기소개')):
            with self.subTest(over):
                self.reset_paid()
                self.fails('E-ME-18', self.good_18(**over), word)

    def test_18_fails_when_the_bio_is_not_saved_or_not_trimmed(self):
        self.fails('E-ME-18', lambda job: said(title='프로필 편집', manage_bios=[job['bio'].strip()]), 'DB 자기소개')

    def test_18_fails_when_the_vector_row_is_not_remade_in_any_of_its_three_ways(self):
        for flag, value, word in (('embeds', False, 'updated_at'), ('embeds', False, 'self_embedding'), ('stamp_time', False, 'updated_at'),
                                  ('change_vector', False, 'self_embedding')):
            with self.subTest((flag, word)):
                self.reset_paid()
                setattr(self.fake, flag, value)
                self.fails('E-ME-18', self.good_18(), word)
                setattr(self.fake, flag, True)

    def test_18_forgives_a_db_clock_a_minute_behind_but_not_five_minutes(self):
        self.fake.clock = timedelta(seconds=-60)
        self.passes('E-ME-18', self.good_18())
        self.reset_paid()
        self.fake.clock = timedelta(minutes=-5)
        self.fails('E-ME-18', self.good_18(), '앱을 켠 시각')

    def test_18_is_blocked_when_the_vector_row_is_missing_or_cannot_be_planted(self):
        self.fake.handlers.insert(0, ('GET', re.compile(r'/rest/v1/profile_vectors'), Reply(200, [])))
        self.blocked('E-ME-18', said(), '준비', '벡터')
        self.fake.handlers.pop(0)
        self.swallow('PATCH', r'/rest/v1/profile_vectors')
        self.blocked('E-ME-18', said(), '준비', '심지 못')


# ── E-ME-19 · 34 키만 고치기 ─────────────────────────────────────────────────────────────────────────

class HeightOnlyTest(ActBase):
    def good(self, **over):
        def answer(job):
            self.assertEqual(self.profile()['height_cm'], 178)  # 앱이 켜지기 전에 PC 가 178 로
            reply = self.api('PATCH', '/me/profile', {'height_cm': int(job['height'])})  # 닉네임은 안 보낸다(바뀐 칸만)
            self.assertEqual(reply[0], 200)
            return said(**{'before': '178', 'save_enabled': True, 'toast_seen': True, 'toast_ms': 2000, 'title': '프로필 편집', **over})
        return answer

    def test_19_changing_only_the_height_keeps_the_vector_row_as_it_was(self):
        note, app = self.passes('E-ME-19', self.good())
        self.assertEqual(app.jobs[0], {'token_hash': 'h', 'height': '180'})
        self.assertTrue(self.vectors()['self_embedding'].startswith(PLANTED))
        self.assertEqual(self.profile()['height_cm'], 180)
        self.assertEqual(self.fake.paid_calls, 0)  # 키만 고치면 임베딩을 안 부른다 — 유료 문이 필요 없다
        self.assertEqual(len(self.fake.by('PATCH', '/me/profile')), 1)

    def test_19_fails_when_the_vector_row_was_touched_or_the_height_was_not_saved_or_the_screen_is_wrong(self):
        def touches(job):
            self.good()(job)
            self.fake.embed('id-1')
            return said(before='178', save_enabled=True, title='프로필 편집')
        self.fails('E-ME-19', touches, 'updated_at', 'self_embedding')
        self.fails('E-ME-19', lambda job: said(before='178', save_enabled=True, title='프로필 편집'), 'DB 키')
        for over, word in (({'title': '기본 정보 수정'}, '15-5'), ({'before': '170'}, '처음 키 칸'), ({'save_enabled': False}, '저장')):
            with self.subTest(over):
                self.fails('E-ME-19', self.good(**over), word)

    def test_19_fails_when_only_the_time_or_only_the_vector_changed(self):
        for flag, word in (('change_vector', 'updated_at'), ('stamp_time', 'self_embedding')):
            with self.subTest(flag):
                setattr(self.fake, flag, False)

                def touches(job, word=word):
                    self.good()(job)
                    self.fake.embed('id-1')
                    return said(before='178', save_enabled=True, title='프로필 편집')
                self.fails('E-ME-19', touches, word)
                setattr(self.fake, flag, True)

    def test_19_is_blocked_when_the_row_is_missing_or_the_height_cannot_be_set(self):
        self.fake.handlers.insert(0, ('GET', re.compile(r'/rest/v1/profile_vectors'), Reply(200, [])))
        self.blocked('E-ME-19', said(), '준비', '벡터')
        self.fake.handlers.pop(0)
        self.swallow('PATCH', r'/rest/v1/profiles')
        self.blocked('E-ME-19', said(), '준비', '키')

    # 34
    def good34(self, **over):
        def answer(job):
            row = self.profile()
            assert datetime.now(timezone.utc) - datetime.fromisoformat(row['nickname_changed_at']) > timedelta(days=39), row
            reply = self.api('PATCH', '/me/profile', {'height_cm': int(job['height'])})
            self.assertEqual(reply[0], 200)
            return said(**{'before': '178', 'save_enabled': True, 'toast_seen': True, 'toast_ms': 2000, 'title': '프로필 편집', **over})
        return answer

    def test_34_the_lock_clock_does_not_restart_when_only_the_height_changes(self):
        _, app = self.passes('E-ME-34', self.good34())
        self.assertEqual(app.jobs[0], {'token_hash': 'h', 'height': '180'})
        row = self.profile()
        self.assertEqual(row['height_cm'], 180)
        self.assertLess(now() - datetime.fromisoformat(row['nickname_changed_at']), timedelta(days=41))
        self.assertGreater(now() - datetime.fromisoformat(row['nickname_changed_at']), timedelta(days=39))

    def test_34_fails_when_the_lock_restarted_the_nickname_changed_or_the_height_is_not_saved(self):
        def restarts(job):
            self.good34()(job)
            self.profile()['nickname_changed_at'] = now().isoformat()
            return said(before='178', save_enabled=True, title='프로필 편집')
        self.fails('E-ME-34', restarts, 'nickname_changed_at')

        def renames(job):
            self.good34()(job)
            self.profile()['nickname'] = 'Changed'
            return said(before='178', save_enabled=True, title='프로필 편집')
        self.fails('E-ME-34', renames, '닉네임')
        self.fails('E-ME-34', lambda job: said(before='178', save_enabled=True, title='프로필 편집'), 'DB 키')
        for over, word in (({'title': '설정'}, '15-5'), ({'before': '170'}, '처음 키 칸'), ({'save_enabled': False}, '저장')):
            with self.subTest(over):
                self.fails('E-ME-34', self.good34(**over), word)

    def test_34_is_blocked_when_the_lock_value_could_not_be_planted(self):
        self.swallow('PATCH', r'/rest/v1/profiles')
        self.blocked('E-ME-34', said(), '준비')


# ── E-ME-20 · 23 자기소개 칸 ─────────────────────────────────────────────────────────────────────────

class BioFieldTest(ActBase):
    def good20(self, **over):
        return said(**{'clear_enabled': False, 'spaces_enabled': False, 'typed_enabled': True, **over})

    def test_20_an_empty_or_blank_bio_turns_the_button_off_and_the_server_says_422_and_keeps_the_text(self):
        _, app = self.passes('E-ME-20', self.good20())
        self.assertEqual(app.jobs, [{'token_hash': 'h'}])
        sent = [s for s in self.fake.by('PATCH', '/me/profile')]
        self.assertEqual([(s['body'], s['auth']) for s in sent], [({'bio': '   '}, 'tok-1')])
        self.assertEqual(self.profile()['bio'], OLD_BIO)
        self.assertEqual([o for m, u, o in self.options if m == 'PATCH' and u.endswith('/me/profile')], [{'retry': False}])  # 한 번만

    def test_20_fails_on_a_button_that_stays_on_or_one_that_never_turns_on(self):
        for over, word in (({'clear_enabled': True}, '비운'), ({'spaces_enabled': True}, '공백'), ({'typed_enabled': False}, '글을 쓰면')):
            with self.subTest(over):
                self.fails('E-ME-20', self.good20(**over), word)

    def test_20_fails_when_the_server_takes_the_blank_text(self):
        self.fake.accepts_blank = True
        self.fails('E-ME-20', self.good20(), '422')

    def test_20_fails_when_the_422_is_for_another_reason_or_the_text_changed(self):
        self.fake.handlers.insert(0, ('PATCH', re.compile(r'/me/profile'), Reply(422, {'detail': [{'msg': 'Value error, 다른 이유'}]})))
        self.fails('E-ME-20', self.good20(), '문구')
        self.fake.handlers.pop(0)

        def overwrites(job):
            self.profile()['bio'] = '바뀐 글'
            return self.good20()
        self.fails('E-ME-20', overwrites, 'DB 자기소개')

    # 23
    def good23(self, **over):
        def answer(job):
            return said(**{'first_field': self.profile()['bio'], 'typed_field': job['typed'], 'reopened_field': self.profile()['bio'], **over})
        return answer

    def test_23_a_half_typed_text_is_gone_when_the_screen_is_opened_again_and_the_server_text_is_back(self):
        _, app = self.passes('E-ME-23', self.good23())
        job = app.jobs[0]
        self.assertEqual(job['token_hash'], 'h')
        self.assertTrue(job['typed'])
        self.assertNotEqual(job['typed'], OLD_BIO)
        self.assertEqual(self.profile()['bio'], OLD_BIO)

    def test_23_fails_when_the_typed_text_stays_or_the_first_open_is_wrong_or_the_typing_never_happened(self):
        typed = lambda job: job['typed']
        self.fails('E-ME-23', lambda job: self.good23(reopened_field=job['typed'])(job), '다시 연')
        self.fails('E-ME-23', lambda job: self.good23(reopened_field='')(job), '다시 연')
        self.fails('E-ME-23', lambda job: self.good23(first_field='')(job), '처음 연')
        self.fails('E-ME-23', lambda job: self.good23(typed_field=OLD_BIO)(job), '치지 못')

    def test_23_fails_when_the_text_was_saved(self):
        def saves(job):
            self.profile()['bio'] = job['typed']
            return said(first_field=OLD_BIO, typed_field=job['typed'], reopened_field=job['typed'])
        self.fails('E-ME-23', saves, 'DB 자기소개')


# ── E-ME-21 태그 편집 ────────────────────────────────────────────────────────────────────────────────

class TagEditTest(ActBase):
    def good(self, **over):
        def answer(job):
            start = sorted(self.profile()['interest_tags'])
            assert len(start) == 4, start  # 앱이 켜지기 전에 PC 가 4개로
            five = sorted(start + [job['extra']])
            reply = self.api('POST', '/profile-onboarding/interests', {'tags': five})
            self.assertEqual(reply[0], 200)
            row = self.profile()
            chips = five + list(row['my_traits']) + list(row['ideal_traits'])
            return said(**{'start': start, 'five': five, 'after_sixth': five, 'two': five[:2], 'two_save_enabled': False,
                           'back_to_five': five, 'title': '자기소개·태그 수정', 'chips': chips, **over})
        return answer

    def test_21_one_more_tag_saves_five_in_place_two_turns_save_off_and_a_sixth_is_not_picked(self):
        _, app = self.passes('E-ME-21', self.good())
        job = app.jobs[0]
        self.assertEqual(job['token_hash'], 'h')
        start = sorted(['카페가기', '자전거', '패션', '반려동물'])
        self.assertNotIn(job['extra'], start)
        self.assertNotIn(job['sixth'], start + [job['extra']])
        self.assertEqual(sorted(self.profile()['interest_tags']), sorted(start + [job['extra']]))

    def test_21_fails_on_each_wrong_step(self):
        cases = (({'start': ['카페가기']}, '처음'), ({'five': ['카페가기']}, '1개 더'), ({'after_sixth': ['카페가기']}, '6번째'),
                 ({'two': ['카페가기']}, '2개'), ({'two_save_enabled': True}, '저장'), ({'back_to_five': ['카페가기']}, '되돌'),
                 ({'title': '설정'}, '15c'), ({'chips': ['카페가기']}, '칩'))
        for over, word in cases:
            with self.subTest(over):
                self.fails('E-ME-21', self.good(**over), word)

    def test_21_fails_when_the_chips_on_15c_are_six_or_the_db_holds_six_or_the_save_did_not_happen(self):
        def six(job):
            said_ = self.good()(job)
            said_['chips'] = said_['chips'] + ['덤']
            return said_
        self.fails('E-ME-21', six, '칩')

        def not_saved(job):
            answer = self.good()(job)
            self.profile()['interest_tags'] = ['카페가기', '자전거', '패션', '반려동물']
            return answer
        self.fails('E-ME-21', not_saved, 'DB')

    def test_21_is_blocked_when_the_four_tags_could_not_be_planted(self):
        self.swallow('PATCH', r'/rest/v1/profiles')
        self.blocked('E-ME-21', said(), '준비', '4개')


# ── E-ME-24 · 25 선호 조건 ───────────────────────────────────────────────────────────────────────────

IDEAL_BASE = {'preferred_mbti_flags': {}, 'preferred_animal_types': ['dog', 'cat'], 'preferred_impression_types': ['kind']}


class IdealConditionsTest(ActBase):
    def app_saves(self, **fields):
        body = {'preferred_age_min': 22, 'preferred_age_max': 27, 'preferred_height_min': 165, 'preferred_height_max': 180,
                **IDEAL_BASE, **fields}
        self.assertEqual(self.api('POST', '/profile-onboarding/ideal-conditions', body)[0], 200)

    def planted(self):
        row = self.profile()
        assert (row['preferred_age_min'], row['preferred_age_max'], row['preferred_height_min'], row['preferred_height_max']) == (22, 27, 165, 180), row
        assert row['preferred_animal_types'] == ['dog', 'cat'] and row['preferred_impression_types'] == ['kind'], row
        assert PLANTED in self.vectors()['self_embedding']

    def good24(self, **over):
        def answer(job):
            self.planted()
            self.app_saves(preferred_age_min=24, preferred_age_max=30)
            return said(**{'title': '이상형 조건 수정', 'first_age': '22세 ~ 27세', 'first_height': '165cm ~ 180cm', 'changed_age': '24세 ~ 30세',
                           'back_title': '프로필 편집', 'age_note': '24세–30세', 'height_note': '165cm ~ 180cm', **over})
        return answer

    def test_24_opens_with_the_server_values_and_saving_24_to_30_shows_on_15_5_and_remakes_the_vectors(self):
        _, app = self.passes('E-ME-24', self.good24())
        self.assertEqual(app.jobs, [{'token_hash': 'h'}])
        row = self.profile()
        self.assertEqual((row['preferred_age_min'], row['preferred_age_max']), (24, 30))
        self.assertEqual((row['preferred_height_min'], row['preferred_height_max']), (165, 180))
        self.assertEqual(self.vectors()['self_embedding'], NEW_VECTOR)
        self.assertEqual(self.fake.paid_calls, 1)

    def test_24_fails_on_each_wrong_screen_value(self):
        for over, word in (({'title': '이상형 조건'}, '앱바'), ({'first_age': '20세 ~ 30세'}, '처음 나이'), ({'first_height': '150cm 이하 ~ 190cm 이상'}, '처음 키'),
                           ({'changed_age': '22세 ~ 27세'}, '고른 나이'), ({'back_title': '내 프로필'}, '15-5'), ({'age_note': '22세–27세'}, '나이 줄'),
                           ({'age_note': '24세-30세'}, '나이 줄'), ({'height_note': '상관없어요'}, '키 줄')):
            with self.subTest(over):
                self.reset_paid()
                self.fails('E-ME-24', self.good24(**over), word)

    def test_24_fails_on_a_wrong_db_value_a_changed_other_field_or_vectors_not_remade(self):
        def other(job):
            answer = self.good24()(job)
            self.profile()['preferred_age_max'] = 31
            return answer
        self.fails('E-ME-24', other, 'DB 나이')
        for tweak, word in ((lambda row: row.update(preferred_height_max=185), 'DB 키'),
                            (lambda row: row.update(preferred_animal_types=['dog']), '얼굴상'),
                            (lambda row: row.update(preferred_impression_types=['chic']), '인상')):
            with self.subTest(word):
                self.reset_paid()

                def changes(job, tweak=tweak):
                    answer = self.good24()(job)
                    tweak(self.profile())
                    return answer
                self.fails('E-ME-24', changes, word)
        for flag, word in (('embeds', 'updated_at'), ('stamp_time', 'updated_at'), ('change_vector', 'self_embedding')):
            with self.subTest(flag):
                self.reset_paid()
                setattr(self.fake, flag, False)
                self.fails('E-ME-24', self.good24(), word)
                setattr(self.fake, flag, True)

    def test_24_is_blocked_when_the_conditions_could_not_be_planted(self):
        self.swallow('PATCH', r'/rest/v1/profiles')
        self.blocked('E-ME-24', said(), '준비')

    # 25
    def good25(self, **over):
        def answer(job):
            self.planted()
            self.app_saves(preferred_age_min=19, preferred_age_max=35, preferred_height_min=None, preferred_height_max=None)
            return said(**{'age_ignored': True, 'height_ignored': True, 'back_title': '프로필 편집', 'age_note': '상관없어요',
                           'height_note': '상관없어요', **over})
        return answer

    def test_25_ignoring_age_and_height_saves_19_to_35_and_empty_heights_and_15_5_says_anything_twice(self):
        _, app = self.passes('E-ME-25', self.good25())
        self.assertEqual(app.jobs, [{'token_hash': 'h'}])
        row = self.profile()
        self.assertEqual((row['preferred_age_min'], row['preferred_age_max'], row['preferred_height_min'], row['preferred_height_max']),
                         (19, 35, None, None))
        self.assertEqual(self.fake.paid_calls, 1)

    def test_25_fails_on_each_wrong_screen_value(self):
        for over, word in (({'age_ignored': False}, '나이 체크'), ({'height_ignored': False}, '키 체크'), ({'back_title': '설정'}, '15-5'),
                           ({'age_note': '19세–35세 이상'}, '나이 줄'), ({'height_note': '150cm 이하 ~ 190cm 이상'}, '키 줄')):
            with self.subTest(over):
                self.reset_paid()
                self.fails('E-ME-25', self.good25(**over), word)

    def test_25_fails_on_a_wrong_db_value_or_vectors_not_remade(self):
        for fields, word in (({'preferred_age_min': 20, 'preferred_age_max': 35, 'preferred_height_min': None, 'preferred_height_max': None}, 'DB 나이'),
                             ({'preferred_age_min': 19, 'preferred_age_max': 34, 'preferred_height_min': None, 'preferred_height_max': None}, 'DB 나이'),
                             ({'preferred_age_min': 19, 'preferred_age_max': 35, 'preferred_height_min': 150, 'preferred_height_max': None}, 'DB 키'),
                             ({'preferred_age_min': 19, 'preferred_age_max': 35, 'preferred_height_min': None, 'preferred_height_max': 190}, 'DB 키')):
            with self.subTest(fields):
                self.reset_paid()

                def saves(job, fields=fields):
                    self.planted()
                    self.app_saves(**fields)
                    return said(age_ignored=True, height_ignored=True, back_title='프로필 편집', age_note='상관없어요', height_note='상관없어요')
                self.fails('E-ME-25', saves, word)
        self.reset_paid()
        self.fake.embeds = False
        self.fails('E-ME-25', self.good25(), 'updated_at')


# ── E-ME-26 얼굴상 · 인상 개수 ───────────────────────────────────────────────────────────────────────

class AppearanceCountTest(ActBase):
    def good(self, **over):
        def answer(job):
            return said(**{'animal_start': ['dog'], 'animal_zero': [], 'animal_zero_save': False,
                           'animal_three': ['cat', 'fox', 'bear'], 'animal_four': ['cat', 'fox', 'bear'],
                           'impression_start': ['kind'], 'impression_zero': [], 'impression_zero_save': False,
                           'impression_three': ['arab', 'tofu', 'chic'], 'impression_four': ['arab', 'tofu', 'chic'],
                           'three_save': True, **over})
        return answer

    def test_26_zero_turns_save_off_and_a_fourth_is_not_picked_for_both_and_the_server_says_422_to_four(self):
        _, app = self.passes('E-ME-26', self.good())
        self.assertEqual(app.jobs, [{'token_hash': 'h'}])
        row = self.profile()
        self.assertEqual((row['preferred_animal_types'], row['preferred_impression_types']), (['dog'], ['kind']))  # 저장하지 않았다
        posts = self.fake.by('POST', '/profile-onboarding/ideal-conditions')
        self.assertEqual(len(posts), 3)  # 계정 공장의 온보딩 한 번 + PC 가 보낸 둘
        self.assertEqual([len(s['body']['preferred_animal_types']) + len(s['body']['preferred_impression_types']) for s in posts[1:]], [5, 5])
        self.assertEqual([s['auth'] for s in posts[1:]], ['tok-1', 'tok-1'])
        self.assertEqual([o for m, u, o in self.options if m == 'POST' and u.endswith('/ideal-conditions')][1:], [{'retry': False}] * 2)
        self.assertEqual(self.fake.paid_calls, 0)  # 422 는 임베딩 앞에서 끝난다

    def test_26_fails_on_each_wrong_step(self):
        for over, word in (({'animal_start': ['dog', 'cat']}, '얼굴상 처음'), ({'animal_zero': ['dog']}, '얼굴상 끄고'), ({'animal_zero_save': True}, '얼굴상 0개'),
                           ({'animal_three': ['cat', 'fox']}, '얼굴상 3개'), ({'animal_four': ['cat', 'fox', 'bear', 'rabbit']}, '얼굴상 4번째'),
                           ({'impression_start': ['kind', 'chic']}, '인상 처음'), ({'impression_zero': ['kind']}, '인상 끄고'),
                           ({'impression_zero_save': True}, '인상 0개'), ({'impression_three': ['arab']}, '인상 3개'),
                           ({'impression_four': ['arab', 'tofu', 'chic', 'innocent']}, '인상 4번째'), ({'three_save': False}, '3개씩')):
            with self.subTest(over):
                self.fails('E-ME-26', self.good(**over), word)

    def test_26_fails_when_the_server_takes_four_or_the_saved_values_changed(self):
        self.fake.accepts_many_types = True
        self.fails('E-ME-26', self.good(), '422')
        self.fake.accepts_many_types = False

        def saves(job):
            self.profile()['preferred_animal_types'] = ['dog', 'cat']
            return self.good()(job)
        self.fails('E-ME-26', saves, 'DB')

    def test_26_fails_when_the_422_is_for_another_reason(self):
        def other(sent):  # 계정 공장의 정상 요청은 그대로, 4개짜리만 다른 이유의 422
            many = max(len(sent['body']['preferred_animal_types']), len(sent['body']['preferred_impression_types'])) > 3
            return Reply(422, {'detail': [{'msg': 'field required'}]}) if many else self.fake._ideal(sent)
        self.fake.handlers.insert(0, ('POST', re.compile(r'/profile-onboarding/ideal-conditions'), other))
        self.fails('E-ME-26', self.good(), '문구')



# ── E-ME-27 · 31 · 33 닉네임 ─────────────────────────────────────────────────────────────────────────

class NicknameChangeTest(ActBase):
    def good(self, **over):
        def answer(job):
            assert unlocked(self.fake), self.profile()  # 앱이 켜지기 전에 잠금을 풀어 둔 상태(공장 계정은 처음부터 잠겨 있다)
            reply = self.api('PATCH', '/me/profile', {'nickname': job['nickname']})
            self.assertEqual(reply[0], 200)
            return said(**{'ok': True, 'field': job['nickname'], 'save_enabled': True, 'toast_seen': True, 'toast_ms': 2000,
                           'title': '프로필 편집', **over})
        return answer

    def test_27_a_free_korean_nickname_is_saved_with_the_toast_and_the_lock_clock_starts_now(self):
        _, app = self.passes('E-ME-27', self.good())
        job = app.jobs[0]
        self.assertEqual(job['token_hash'], 'h')
        self.assertRegex(job['nickname'], r'^[가-힣]{2,5}$')  # 계정 공장의 영문 5자와 겹칠 수 없다
        row = self.profile()
        self.assertEqual(row['nickname'], job['nickname'])
        self.assertLess(abs(now() - datetime.fromisoformat(row['nickname_changed_at'])), timedelta(minutes=1))
        self.assertIn(job['nickname'], self.fake.names)  # PC 가 안 쓰는 이름인지 먼저 물었다

    def test_27_a_nickname_somebody_uses_is_skipped_for_another(self):
        self.fake.taken_names = {'가나다'}
        taken = []
        original = area5_act.random.choices

        def always_same(population, k):
            taken.append(1)
            return list('가나다') if len(taken) == 1 else original(population, k=k)
        with mock.patch.object(area5_act.random, 'choices', always_same):
            _, app = self.passes('E-ME-27', self.good())
        self.assertNotEqual(app.jobs[0]['nickname'], '가나다')

    def test_27_fails_on_each_wrong_screen_value(self):
        for over, word in (({'ok': False}, '사용할 수 있는'), ({'save_enabled': False}, '저장 버튼'), ({'toast_seen': False}, '저장했어요'),
                           ({'toast_ms': 100}, '토스트'), ({'toast_ms': 9000}, '토스트'), ({'title': '기본 정보 수정'}, '15-5')):
            with self.subTest(over):
                self.fails('E-ME-27', self.good(**over), word)

    def test_27_fails_when_the_nickname_or_the_lock_clock_is_wrong(self):
        self.fails('E-ME-27', lambda job: said(ok=True, field=job['nickname'], save_enabled=True, toast_seen=True, toast_ms=2000, title='프로필 편집'),
                   'DB 닉네임')
        self.fake.stamps_nickname = False
        self.fails('E-ME-27', self.good(), 'nickname_changed_at')
        self.fake.stamps_nickname = True

        def early(job):
            answer = self.good()(job)
            self.profile()['nickname_changed_at'] = (now() - timedelta(days=2)).isoformat()
            return answer
        self.fails('E-ME-27', early, 'nickname_changed_at')

    def test_27_is_blocked_when_the_lock_cannot_be_lifted_or_no_free_name_is_found(self):
        self.swallow('PATCH', r'/rest/v1/profiles')
        self.blocked('E-ME-27', said(), '준비', '풀리는 때')
        self.fake.handlers.pop(0)
        self.fake.always_taken = True
        self.blocked('E-ME-27', said(), '준비', '닉네임')

    # 31
    def midway(self, **over):
        events = self.events

        def answer(job):
            at = self.profile()['nickname_changed_at']
            assert at and abs(now() - datetime.fromisoformat(at)) < timedelta(minutes=1), at  # 멈춘 사이 PC 가 잠금을 걸었다
            reply = self.api('PATCH', '/me/profile', {'nickname': job['nickname']})
            self.assertEqual((reply[0], reply[1]), (409, {'detail': SOON}))
            return said(**{'enabled_at_open': True, 'ok_before': True, 'error': True, 'error_icon': True, 'error_color': ERROR_COLOR,
                            'on_edit': True, 'title': '기본 정보 수정', **over})
        return MidwayApp(answer, 'opened', events)

    def test_31_when_the_lock_arrives_while_the_screen_is_open_the_save_is_refused_with_the_red_line_and_nothing_changes(self):
        _, app = self.passes('E-ME-31', None, self.midway())
        self.assertEqual(self.events, ['step', 'go'])
        self.assertTrue(app.midway_given)
        row = self.profile()
        self.assertNotEqual(row['nickname'], app.jobs[0]['nickname'])
        self.assertRegex(app.jobs[0]['nickname'], r'^[가-힣]{2,5}$')

    def test_31_the_lock_is_put_in_while_the_app_waits_and_not_before(self):
        # 앱이 켜지는 순간(멈추기 전)에는 잠금이 풀려 있다 — 멈춘 사이에 PC 가 건다. 그래서 앱이 연 15-6 의 닉네임 칸은 켜져 있고 저장할 때만 막힌다.
        order = []
        inner = self.midway()

        class Spy(MidwayApp):
            def __call__(spy, midway=None, **job):
                order.append(unlocked(self.fake))
                return super().__call__(midway, **job)
        spy = Spy(inner.answer, 'opened', self.events)
        self.passes('E-ME-31', None, spy)
        self.assertEqual(order, [True])
        self.assertFalse(unlocked(self.fake))  # 끝난 뒤에는 PC 가 건 잠금

    def test_31_fails_on_each_wrong_screen_value(self):
        for over, word in (({'enabled_at_open': False}, '열었을 때'), ({'ok_before': False}, '사용할 수 있는'), ({'error': False}, '닉네임은 30일'),
                           ({'error_icon': False}, '오류 줄'),
                           ({'error_color': 0xFF222222}, '빨간'), ({'error_color': None}, '빨간'), ({'on_edit': False}, '머물'),
                           ({'title': '프로필 편집'}, '머물')):
            with self.subTest(over):
                self.fails('E-ME-31', None, word, app=self.midway(**over))

    def test_31_fails_when_the_nickname_changed_or_the_lock_was_overwritten(self):
        app = self.midway()
        inner = app.answer

        def renames(job):
            answer = inner(job)
            self.profile()['nickname'] = job['nickname']
            return answer
        app.answer = renames
        self.fails('E-ME-31', None, 'DB 닉네임', app=app)

        app = self.midway()
        inner = app.answer

        def restamps(job):
            answer = inner(job)
            self.profile()['nickname_changed_at'] = (now() + timedelta(days=1)).isoformat()
            return answer
        app.answer = restamps
        self.fails('E-ME-31', None, 'nickname_changed_at', app=app)

    def test_31_is_blocked_when_the_lock_cannot_be_put_in_during_the_pause(self):
        app = MidwayApp(as_fn(said()), 'opened', self.events)
        self.fake.handlers.insert(0, ('PATCH', re.compile(r'/rest/v1/profiles'), lambda sent: self.fake._table('PATCH', 'profiles', sent)
                                      if sent['body'].get('nickname_changed_at') is None else Reply(500, {'message': 'down'})))
        self.blocked('E-ME-31', None, '바꾸기 500', app=app)

    # 33
    @staticmethod
    def probe(typed, **over):
        field = re.sub(r'[^가-힣a-zA-Zㄱ-ㅎㅏ-ㅣ]', '', typed)  # 입력칸이 걸러 내는 글자(basic_info_screen.dart nicknameInputFormatters)
        valid = bool(NICK.fullmatch(field))
        return {'typed': typed, 'field': field, 'ok': valid, 'bad': not valid, 'taken': False, 'save_enabled': valid, **over}

    def answers33(self, job, change=None):
        out = [self.probe(typed) for typed in job['typed']]
        for index, over in (change or {}).items():
            out[index] = {**out[index], **over}
        return said(probes=out)

    def test_33_two_to_five_letters_pass_and_the_rest_are_refused_and_digits_and_marks_never_reach_the_field(self):
        note, app = self.passes('E-ME-33', lambda job: self.answers33(job))
        self.assertEqual(app.jobs[0]['typed'], ['가', '가나다라마바', 'abc1', '하늘!', '하늘', 'Sky'])
        self.assertIn('걸러', note)  # 시나리오와 다른 점(숫자 · 기호는 입력칸이 걸러 낸다)을 메모로 남긴다
        self.assertEqual(self.fake.by('PATCH', '/me/profile'), [])  # 저장하지 않는다
        self.assertTrue({'abc', 'Sky', '하늘'} <= set(self.fake.names))  # 통과할 이름이 이미 쓰이는 이름이 아닌지 PC 가 먼저 물었다

    def test_33_a_field_that_does_not_filter_is_fine_when_it_shows_the_error_and_keeps_save_off(self):
        unfiltered = {2: {'field': 'abc1', 'ok': False, 'bad': True, 'save_enabled': False},
                      3: {'field': '하늘!', 'ok': False, 'bad': True, 'save_enabled': False}}
        self.passes('E-ME-33', lambda job: self.answers33(job, unfiltered))

    def test_33_fails_on_each_wrong_probe(self):
        for index, over, word in (
                (0, {'ok': True, 'bad': False, 'save_enabled': True}, "'가'"), (0, {'save_enabled': True}, "'가'"), (0, {'bad': False}, "'가'"),
                (0, {'ok': True}, "'가'"),
                (1, {'bad': False}, "'가나다라마바'"), (1, {'save_enabled': True}, "'가나다라마바'"),
                (4, {'bad': True}, "'하늘'"), (4, {'bad': True, 'ok': False}, "'하늘'"), (4, {'save_enabled': False}, "'하늘'"), (5, {'ok': False}, "'Sky'"),
                (5, {'taken': True}, "'Sky'"),
                # 걸러지지 않았는데 오류도 안 띄우고 저장도 켜 둔다 — 시나리오가 막으려는 바로 그것
                (2, {'field': 'abc1'}, "'abc1'"), (3, {'field': '하늘!', 'save_enabled': True}, "'하늘!'"),
                (2, {'field': 'abcd'}, "'abc1'")):
            with self.subTest((index, str(over))):
                self.fails('E-ME-33', lambda job, index=index, over=over: self.answers33(job, {index: over}), word)

    def test_33_fails_when_the_app_reports_fewer_probes_than_asked(self):
        self.fails('E-ME-33', lambda job: said(probes=[self.probe('가')]), '하늘')

    def test_33_is_blocked_when_a_passing_name_is_already_used_or_the_lock_cannot_be_lifted(self):
        self.fake.taken_names = {'sky'}  # 대소문자만 다른 것도 같은 이름이다
        self.blocked('E-ME-33', lambda job: self.answers33(job), '준비', 'Sky')
        self.fake.taken_names = set()
        self.swallow('PATCH', r'/rest/v1/profiles')
        self.blocked('E-ME-33', lambda job: self.answers33(job), '준비', '풀리는 때')


# ── E-ME-35 · 36 키 칸 ───────────────────────────────────────────────────────────────────────────────

class HeightFieldTest(ActBase):
    def rows(self, **over):
        return [{'typed': '119', 'error': True, 'save_enabled': False},
                {'typed': '231', 'error': True, 'save_enabled': False},
                {'typed': '120', 'error': False, 'save_enabled': True, 'title': '프로필 편집', 'reopened': '120'},
                {'typed': '230', 'error': False, 'save_enabled': True, 'title': '프로필 편집', 'reopened': '230'}]

    def good35(self, changes=None, save=True):
        def answer(job):
            assert self.profile()['height_cm'] == 178
            rows = self.rows()
            for index, over in (changes or {}).items():
                rows[index] = {**rows[index], **over}
            if save:
                for typed in job['good']:
                    self.assertEqual(self.api('PATCH', '/me/profile', {'height_cm': int(typed)})[0], 200)
            return said(rows=rows)
        return answer

    def test_35_119_and_231_are_refused_and_120_and_230_are_saved_and_the_server_says_422_to_300(self):
        _, app = self.passes('E-ME-35', self.good35())
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'bad': ['119', '231'], 'good': ['120', '230']}])
        self.assertEqual(self.profile()['height_cm'], 230)
        sent = self.fake.by('PATCH', '/me/profile')
        self.assertEqual([s['body'] for s in sent], [{'height_cm': 120}, {'height_cm': 230}, {'height_cm': 300}])
        self.assertEqual([o for m, u, o in self.options if m == 'PATCH' and u.endswith('/me/profile')][-1], {'retry': False})

    def test_35_fails_on_each_wrong_row(self):
        for index, over, word in ((0, {'error': False}, "'119'"), (0, {'save_enabled': True}, "'119'"), (1, {'error': False}, "'231'"),
                                  (1, {'save_enabled': True}, "'231'"), (2, {'error': True}, "'120'"), (2, {'save_enabled': False}, "'120'"),
                                  (2, {'title': '기본 정보 수정'}, "'120'"), (2, {'reopened': '178'}, "'120'"), (3, {'error': True}, "'230'"),
                                  (3, {'save_enabled': False}, "'230'"), (3, {'reopened': '120'}, "'230'")):
            with self.subTest((index, str(over))):
                self.fails('E-ME-35', self.good35({index: over}), word)

    def test_35_fails_when_the_app_says_fewer_rows_or_the_final_height_is_wrong(self):
        self.fails('E-ME-35', lambda job: said(rows=[]), "'119'", "'230'")
        self.fails('E-ME-35', self.good35(save=False), 'DB 키')

    def test_35_fails_when_the_server_takes_300_or_answers_with_another_text(self):
        self.fake.accepts_any_height = True
        self.fails('E-ME-35', self.good35(), '422')
        self.fake.accepts_any_height = False
        self.fake.handlers.insert(0, ('PATCH', re.compile(r'/me/profile'), lambda sent: Reply(422, {'detail': '다른 문구'})
                                      if sent['body'].get('height_cm') == 300 else self.fake._patch_me(sent)))
        self.fails('E-ME-35', self.good35(), '문구')

    def test_35_fails_when_the_300_changed_the_height(self):
        self.fake.accepts_any_height = True
        self.fails('E-ME-35', self.good35(), 'DB 키')

    def test_35_is_blocked_when_the_height_cannot_be_set(self):
        self.swallow('PATCH', r'/rest/v1/profiles')
        self.blocked('E-ME-35', said(), '준비')

    # 36
    def good36(self, **over):
        def answer(job):
            row = self.profile()
            return said(**{'untouched_enabled': False, 'height_changed_enabled': True, 'height_back_enabled': False,
                           'nick_changed_enabled': True, 'nick_back_enabled': False, 'height': str(row['height_cm']),
                           'nickname': row['nickname'], **over})
        return answer

    def test_36_nothing_changed_and_changed_back_both_keep_save_off_and_a_real_change_turns_it_on(self):
        _, app = self.passes('E-ME-36', self.good36())
        job = app.jobs[0]
        self.assertEqual(job['token_hash'], 'h')
        self.assertRegex(job['other'], r'^[가-힣]{2,5}$')
        self.assertNotEqual(job['other'], self.profile()['nickname'])
        self.assertTrue(unlocked(self.fake))  # 닉네임 칸이 켜져 있어야 닉네임 되돌리기도 본다

    def test_36_fails_on_each_wrong_button_state(self):
        for over, word in (({'untouched_enabled': True}, '아무것도'), ({'height_changed_enabled': False}, '키를 바꾸면'),
                           ({'height_back_enabled': True}, '키를 되돌'), ({'nick_changed_enabled': False}, '닉네임을 바꾸면'),
                           ({'nick_back_enabled': True}, '닉네임을 되돌')):
            with self.subTest(over):
                self.fails('E-ME-36', self.good36(**over), word)

    def test_36_fails_when_the_original_the_app_went_back_to_is_not_the_saved_one(self):
        self.fails('E-ME-36', self.good36(height='180'), '원래')
        self.fails('E-ME-36', self.good36(nickname='다른이름'), '원래')

    def test_36_fails_when_the_app_saved_something(self):
        for column, value in (('height_cm', 181), ('nickname', 'Changed')):
            with self.subTest(column):
                def saves(job, column=column, value=value):
                    answer = self.good36()(job)  # 앱은 원래 값을 말하고(키 · 닉네임 칸이 그대로) DB 만 바뀌었다
                    self.profile()[column] = value
                    return answer
                self.fails('E-ME-36', saves, 'DB')

    def test_36_is_blocked_when_the_lock_cannot_be_lifted_or_no_free_name_is_found(self):
        self.swallow('PATCH', r'/rest/v1/profiles')
        self.blocked('E-ME-36', said(), '준비')


# ── 공통 ─────────────────────────────────────────────────────────────────────────────────────────────

class WritesTest(ActBase):
    def test_every_db_write_goes_to_the_account_the_run_made(self):
        # 가짜 서버가 만든 계정(id-1)만 쓰는지 — 쓰기 가드(area2._guard)는 시험에서 빼 두었으니 요청 자체를 본다.
        answers = {
            'E-ME-19': lambda job: said(before='178', save_enabled=True, title='프로필 편집'),
            'E-ME-21': lambda job: said(),
            'E-ME-26': lambda job: said(),
            'E-ME-35': lambda job: said(rows=[]),
            'E-ME-27': lambda job: said(),
        }
        for name, answer in answers.items():
            with self.subTest(name):
                self.case(name, answer)
                self.writes_only_mine()

    def stranger_run(self):
        """진짜 가드로 돌린다 — 이번 실행이 만든 계정 목록(accounts.json)은 비어 있다."""
        patcher = mock.patch.object(area2, '_guard', REAL_GUARD)
        patcher.start()
        self.addCleanup(patcher.stop)
        return {'id': 'stranger-1'}

    def test_write_refuses_an_account_this_run_did_not_make_and_sends_nothing(self):
        stranger = self.stranger_run()
        with self.assertRaises(tools.Blocked) as caught:
            area5_act._write(self.run_, stranger, {'height_cm': 180})
        self.assertIn('stranger-1', str(caught.exception))
        self.assertEqual(self.fake.sent, [])

    def test_plant_vectors_refuses_an_account_this_run_did_not_make_and_sends_nothing(self):
        stranger = self.stranger_run()
        with self.assertRaises(tools.Blocked) as caught:
            area5_act._plant_vectors(self.run_, stranger)
        self.assertIn('stranger-1', str(caught.exception))
        self.assertEqual(self.fake.sent, [])

    def test_write_and_plant_vectors_go_through_for_an_account_this_run_made(self):
        # 위 둘이 "무엇이든 막는" 시험이 아니라는 대조 — 이번 실행이 만든 계정이면 쓴다.
        mine = self.stranger_run()
        self.run_.out.mkdir(parents=True, exist_ok=True)
        (self.run_.out / 'accounts.json').write_text(json.dumps([mine]), encoding='utf-8')
        self.fake.profile('stranger-1')
        self.fake.rows('profile_vectors').append({'profile_id': 'stranger-1', 'updated_at': now().isoformat(), 'self_embedding': 'x'})
        area5_act._write(self.run_, mine, {'height_cm': 180})
        area5_act._plant_vectors(self.run_, mine)
        self.assertEqual(self.fake.profile('stranger-1')['height_cm'], 180)
        self.assertIn('[1,0,0,0', self.vectors_of_id('stranger-1')['self_embedding'])

    def vectors_of_id(self, who):
        return next(r for r in self.fake.rows('profile_vectors') if r['profile_id'] == who)

    def test_the_guard_is_called_before_every_write_the_module_does(self):
        guarded = []
        with mock.patch.object(area2, '_guard', lambda run, *ids: guarded.extend(ids)):
            self.case('E-ME-19', lambda job: said(before='178', save_enabled=True, title='프로필 편집'))
        self.assertIn('id-1', guarded)


class AppAnswerTest(ActBase):
    """한 번 켜서 한 번 말하는 열넷 · 한 번 멈추는 하나 — 앱의 blocked 는 blocked, 말이 없으면 fail."""

    def test_a_blocked_app_is_blocked_and_a_silent_or_failed_app_is_a_fail(self):
        for case in BUNDLE:
            with self.subTest(case):
                app = lambda answer: MidwayApp(as_fn(answer), 'opened', self.events) if case == 'E-ME-31' else App(as_fn(answer))
                self.reset_paid()
                self.blocked(case, None, '못 찾음', app=app({'result': 'blocked', 'note': '못 찾음'}))
                self.reset_paid()
                self.fails(case, None, '답하지 않음', app=app(lambda job: None))
                self.reset_paid()
                self.fails(case, None, '앱이 본 것과 다름', app=app({'result': 'fail', 'note': '앱이 본 것과 다름'}))


if __name__ == '__main__':
    unittest.main()
