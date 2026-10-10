"""영역 5 폰 A · 아바타 다시 만들기 3개 + 15-7 사진 수정 6개(E-ME 12 · 13 · 14 · 38 · 39 · 41 · 42 · 44 + E-EDGE-03)의 PC 쪽 시험 —
폰 · 운영 없이 가짜 앱 · 가짜 서버로 돈다. 저장소 루트에서 `python -m unittest e2e.test_area5_photo`.

가짜 서버([PhotoFake])는 area5_act 시험의 [ActFake] 에 이 묶음이 쓰는 서버 규칙 — `POST /me/avatar/regenerate`(me/router.py) · `PUT /me/photos`(me/router.py ·
me/photo_layout.py) · 저장소(profile-photos) 파일 · 하트 원장 · 큐 등록 횟수 · Vision 호출 횟수 — 만 더했다. 가짜 앱은 test_area3_phone.py 의 App(한 번 켜서 한 번 말함) ·
MidwayApp(한 번 멈춤)이고, "앱이 눌렀다" 는 시험이 가짜 앱 안에서 같은 서버 API 를 불러(`self.api` · `self.app_save`) 흉내 낸다. 계정은 id-1 · 토큰 tok-1.
시험의 글자는 모듈에서 가져오지 않고 그대로 적었다 — 모듈의 상수가 틀려도 시험이 잡는다.
"""

import ast
import json
import os
import re
import subprocess
import sys
import threading
import time
import unittest
import uuid
from datetime import timedelta
from pathlib import Path
from unittest import mock
from urllib.parse import urlsplit

from e2e import area1, area2, area4, area5_act, area5_photo, tools
from e2e.area2_phone3 import _PAID
from e2e.test_area1 import CFG
from e2e.test_area3_phone import App, said
from e2e.test_area3_phone2 import MidwayApp, as_fn
from e2e.test_area3_safe import _who
from e2e.test_area5_act import ActBase, ActFake, REAL_GUARD, dart, lib, now
from e2e.test_area5_read import delete_button_violations, server_keys
from e2e.tools import Reply

BUNDLE = ['E-ME-10', 'E-ME-11', 'E-ME-12', 'E-ME-13', 'E-ME-14', 'E-ME-16', 'E-ME-38', 'E-ME-39', 'E-ME-40', 'E-ME-41', 'E-ME-42', 'E-ME-43', 'E-ME-44', 'E-EDGE-03']
PAID = ['E-ME-10', 'E-ME-11', 'E-ME-14', 'E-ME-16', 'E-ME-40']  # 앱이 다시 만들기를 눌러 서버가 큐에 넣고 워커가 OpenAI 이미지를 부를 수 있는 것들
FREE_BODY = '첫 번째 다시 만들기는 무료예요. 새 아바타는 바로 프로필에 반영돼요.'
TITLES = {'15-5': '프로필 편집', '15-7': '사진 수정'}
LOW_TITLE = '하트가 모자라요'
LOW_BODY = '하트 10개가 필요해요. 지금 보유한 하트는 5개예요.'
PAID_TITLE = '아바타를 다시 만들까요?'
FAILED_TOAST = '아바타를 만들지 못했어요.\n하트는 차감되지 않았어요.'
CHANGED = '사진이 바뀌었어요, 다시 열어 주세요'
NETWORK = '네트워크 연결을 확인해 주세요'
MAX_NOTICE = '사진은 최대 4장까지 올릴 수 있어요'
NONE_KEPT = '얼굴이 보이는 사진을 골라 주세요'
ONE_DROPPED = '1장은 얼굴이 보이지 않아 빠졌어요'
INVALID = '입력한 값을 다시 확인해 주세요'
NOT_SAFE = '부적절한 사진은 올릴 수 없어요'
ROOT = tools.ROOT / 'backend' / 'app'


def paid_body(balance):
    return f'하트 10개가 차감돼요. 지금 보유한 하트는 {balance}개예요. 새 아바타는 바로 프로필에 반영돼요.'


def name_of(row):
    return row['storage_path'].rsplit('/', 1)[-1]


def wait_for(check, seconds=5):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if check():
            return True
        time.sleep(0.005)
    return False


def multipart(fields, files=0):
    """앱이 보내는 multipart(PUT /me/photos) — 파일 [files] 개."""
    boundary = uuid.uuid4().hex
    parts = [f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode() for k, v in fields.items()]
    parts += [f'--{boundary}\r\nContent-Disposition: form-data; name="photos"; filename="p{i}.jpg"\r\nContent-Type: image/jpeg\r\n\r\n'.encode()
              + b'\xff\xd8\xff' + f'\r\n'.encode() for i in range(files)]
    return b''.join(parts) + f'--{boundary}--\r\n'.encode(), f'multipart/form-data; boundary={boundary}'


def parse_multipart(data, kind):
    boundary = kind.split('boundary=')[1].encode()
    fields, files = {}, 0
    for part in data.split(b'--' + boundary):
        head, _, value = part.partition(b'\r\n\r\n')
        found = re.search(rb'name="(\w+)"', head)
        if not found:
            continue
        if b'filename=' in head:
            files += 1
        else:
            fields[found.group(1).decode()] = value.rstrip(b'\r\n').decode()
    return {**fields, 'files': files}


def parse_slots(raw, new_count, source):
    """me/photo_layout.py parse_layout 을 따라 한 시험용 사본 — [ServerRulesTest] 가 진짜와 맞대 본다."""
    try:
        slots = json.loads(raw)
    except json.JSONDecodeError as error:
        raise ValueError('json') from error
    if not isinstance(slots, list) or not 2 <= len(slots) <= 4:
        raise ValueError('칸은 2~4개')
    parsed = []
    for slot in slots:
        if isinstance(slot, dict) and slot.keys() == {'keep'} and isinstance(slot['keep'], str):
            parsed.append(slot['keep'])
        elif isinstance(slot, dict) and slot.keys() == {'new'} and type(slot['new']) is int:
            parsed.append(slot['new'])
        else:
            raise ValueError('칸 모양')
    kept = [s for s in parsed if isinstance(s, str)]
    new = [s for s in parsed if isinstance(s, int)]
    if len(set(kept)) != len(kept) or sorted(new) != list(range(new_count)):
        raise ValueError('번호')
    if not 0 <= source < len(parsed):
        raise ValueError('원본')
    return parsed


class PhotoFake(ActFake):
    """ActFake + 이 묶음이 부르는 서버 규칙. 응답 칸 · 문구는 진짜 서버 그대로([FakeShapeTest] 가 맞대 본다)."""

    def __init__(self):
        super().__init__()
        self.storage = {}  # 버킷 → 파일 경로들
        self.vision_calls = 0  # PUT /me/photos 가 부른 SafeSearch 횟수(새 파일마다 한 번)
        self.queued = 0  # POST /me/avatar/regenerate 가 작업 큐에 넣은 횟수
        self.unsafe = False  # 새 사진을 부적절로 보는 Vision
        self.checks_layout = True  # False: 칸 규칙(2~4장 · 모양)을 안 보는 서버
        self.layout_detail = INVALID  # 칸 규칙에 걸렸을 때 422 가 싣는 문구
        self.checks_owner = True  # False: 남길 id 가 내 사진인지 안 보는 서버
        self.checks_hearts = True  # False: 하트가 모자라도 큐에 넣는 서버
        self.deletes_files = True  # False: 뺀 사진 파일을 저장소에서 안 지우는 서버
        self.after_queue = None  # (큐에 넣은 아바타 행) → 그 직후 일어나는 일(빠른 워커 흉내)
        for method, pattern, handler in (('POST', r'/me/avatar/regenerate', self._regenerate), ('PUT', r'/me/photos', self._put_photos)):
            self.on(method, pattern, handler)

    def __call__(self, method, url, headers=None, body=None, raw=None, **options):
        path = urlsplit(url).path
        if path.startswith('/storage/v1/object/'):
            self.sent.append({'method': method, 'path': path, 'query': {}, 'body': body, 'auth': '', 'apikey': None})
            return self._storage(method, path, body)
        if raw and method == 'PUT' and path == '/me/photos':
            body, raw = parse_multipart(*raw), None
        return super().__call__(method, url, headers, body, raw, **options)

    # ── 저장소 ──
    def _storage(self, method, path, body):
        rest = path.removeprefix('/storage/v1/object/')
        if rest.startswith('list/'):
            prefix = body['prefix'] + '/'
            files = self.storage.get(rest.removeprefix('list/'), set())
            return Reply(200, [{'name': p.removeprefix(prefix), 'id': 'f'} for p in sorted(files) if p.startswith(prefix)])
        bucket, _, file = rest.partition('/')
        if method == 'POST':
            self.storage.setdefault(bucket, set()).add(file)
        return Reply(200, None)

    def _photo(self, sent):
        reply = super()._photo(sent)
        self.storage.setdefault('profile-photos', set()).add(self.rows('profile_photos')[-1]['storage_path'])
        return reply

    # ── 하트 ──
    def _grant(self, sent):
        body = sent['body']
        who = body['p_profile_id']
        row = next((r for r in self.rows('entitlements') if r['profile_id'] == who), None)
        have = row['heart_balance'] if row else 0
        if have + body['p_amount'] < 0:
            return Reply(400, {'code': '23514', 'message': 'entitlements_balance_non_negative'})
        if row is None:
            self.rows('entitlements').append({'profile_id': who, 'heart_balance': body['p_amount']})
        else:
            row['heart_balance'] += body['p_amount']
        self.rows('heart_transactions').append({'profile_id': who, 'amount': body['p_amount'], 'reason': body['p_reason'], 'ref_id': body.get('p_ref_id')})
        return Reply(200, None)

    def balance(self, who='id-1'):
        return next((e['heart_balance'] for e in self.rows('entitlements') if e['profile_id'] == who), 0)

    # ── POST /me/avatar/regenerate ──
    def _regenerate(self, sent):
        """me/router.py regenerate_avatar — 설정 → ready 0 → 원본 없음 → 하트(402) → 큐 등록(202)."""
        who = _who(sent)
        ready = self._ready(who)
        if not ready:
            return Reply(409, {'detail': '아바타를 먼저 만들어 주세요'})
        if not any(p['is_avatar_source'] for p in self.rows('profile_photos') if p['profile_id'] == who):
            return Reply(409, {'detail': '아바타 원본 사진을 먼저 골라 주세요'})
        cost = 0 if len(ready) <= 1 else 10
        if cost and self.checks_hearts and self.balance(who) < cost:
            return Reply(402, {'detail': LOW_TITLE})
        if not any(a['profile_id'] == who and a['status'] == 'pending' for a in self.rows('profile_avatars')):
            self._stamp = max(now(), self._stamp + timedelta(microseconds=1))
            row = {'id': str(uuid.uuid4()), 'profile_id': who, 'status': 'pending', 'storage_path': None, 'created_at': self._stamp.isoformat()}
            self.rows('profile_avatars').append(row)
            self.queued += 1
            if self.after_queue:
                self.after_queue(row)
        return Reply(202, {'status': 'pending', 'avatar_url': None, 'compensation_hearts': None})

    # ── PUT /me/photos ──
    def _put_photos(self, sent):
        """me/router.py save_photos — ① 칸 규칙(422) → ② 남길 id(409) → ③ 새 파일마다 Vision → ④ 올리고 · 지우고 · 다시 적는다."""
        who, body = _who(sent), sent['body']
        source = int(body['avatar_source'])
        try:
            slots = parse_slots(body['layout'], body['files'], source)
        except ValueError:
            if self.checks_layout:
                return Reply(422, {'detail': self.layout_detail})
            slots = json.loads(body['layout'])
            slots = [s['keep'] if 'keep' in s else s['new'] for s in slots]
        mine = [p for p in self.rows('profile_photos') if p['profile_id'] == who]
        current = {p['id']: p for p in mine}
        if self.checks_owner and any(isinstance(s, str) and s not in current for s in slots):
            return Reply(409, {'detail': CHANGED})
        for _ in range(body['files']):
            self.vision_calls += 1
            if self.unsafe:
                return Reply(422, {'detail': NOT_SAFE})
        uploaded = []
        for _ in range(body['files']):
            uploaded.append(f'{who}/{uuid.uuid4()}.jpg')
            self.storage.setdefault('profile-photos', set()).add(uploaded[-1])
        kept = {s for s in slots if isinstance(s, str)}
        dropped = [p for p in mine if p['id'] not in kept]
        self.tables['profile_photos'] = [p for p in self.rows('profile_photos') if p not in dropped]
        if self.deletes_files:
            for p in dropped:
                self.storage['profile-photos'].discard(p['storage_path'])
        for position, slot in enumerate(slots):
            if isinstance(slot, str):
                row = current.get(slot) or {'id': slot, 'profile_id': who, 'storage_path': f'{who}/ghost-{slot}.jpg'}
                if row not in self.rows('profile_photos'):
                    self.rows('profile_photos').append(row)
            else:
                row = {'id': str(uuid.uuid4()), 'profile_id': who, 'storage_path': uploaded[slot]}
                self.rows('profile_photos').append(row)
            row.update(position=position, is_avatar_source=position == source)
        return Reply(200, {'ok': True})


class PhotoBase(ActBase):
    def setUp(self):
        super().setUp()
        self.fake = PhotoFake()
        folder = self.root / '사진'  # 사진 세트 폴더(area1_b3.photo_dir)
        folder.mkdir()
        for name in ('face1.jpg', 'scenery.jpg', 'unsafe.jpg'):
            (folder / name).write_bytes(b'\xff\xd8\xff' + name.encode())
        self.folder = folder
        for patcher in (mock.patch.object(area5_photo, 'FLIP_POLL', 0.01),):
            patcher.start()
            self.addCleanup(patcher.stop)

    def case(self, name, answer, app=None):
        fake = self.fake
        fake.storage.clear()
        fake.vision_calls = fake.queued = 0
        return super().case(name, answer, app)

    def midway(self, answer, step):
        return MidwayApp(as_fn(answer), step, self.events)

    # ── 읽기 ──
    def photos(self, n=1):
        """위치 순서대로의 사진 행."""
        return sorted(self.rows('profile_photos', profile_id=f'id-{n}'), key=lambda r: r['position'])

    def avatars(self, n=1, **where):
        return self.rows('profile_avatars', profile_id=f'id-{n}', **where)

    def files(self, n=1):
        return sorted(p for p in self.fake.storage.get('profile-photos', ()) if p.startswith(f'id-{n}/'))

    def ledger(self, reason, n=1):
        return [r['amount'] for r in self.rows('heart_transactions', profile_id=f'id-{n}', reason=reason)]

    # ── 앱이 한 일 흉내 ──
    def app_save(self, layout, source=0, files=0, n=1, expect=200):
        data, kind = multipart({'layout': json.dumps(layout), 'avatar_source': str(source)}, files)
        reply = tools.call('PUT', f"{CFG['API_BASE_URL']}/me/photos", {'Authorization': f'Bearer tok-{n}'}, raw=(data, kind), retry=False)
        self.assertEqual(reply[0], expect, reply)
        return reply

    def call_regenerate(self, n=1):
        return self.api('POST', '/me/avatar/regenerate', {}, n)

    def app_replace_source(self, n=1, expect=200):
        """앱이 사진 고르기에서 사진 한 장을 골라 시트의 "만들기" 를 눌렀을 때 서버가 받는 첫 요청 — 지금 아바타 원본 칸만 새 파일로 바꾼다(PUT /me/photos, 장수 그대로)."""
        rows = self.photos(n)
        source = next(i for i, row in enumerate(rows) if row['is_avatar_source'])
        layout = [{'new': 0} if i == source else {'keep': row['id']} for i, row in enumerate(rows)]
        return self.app_save(layout, source=source, files=1, n=n, expect=expect)

    def pushed_regen_photo(self):
        """폰 앱 캐시로 옮긴 파일 이름들(adb push) — regen_photo 가 한 일."""
        return [Path(call[-2]).name for call in self.adb_calls if len(call) > 2 and call[1] == 'push']

    def good_14(self, **over):
        """앱이 "10 쓰고 만들기" 를 눌러 202 를 받고, PC 가 새 pending 행을 failed 로 바꾸기를 기다린 뒤 15-3 토스트를 본 것처럼."""
        def answer(job):
            self.app_replace_source()  # 사진 교체가 먼저
            self.regen_reply = self.call_regenerate()
            self.assertEqual(self.regen_reply[0], 202)
            self.assertTrue(wait_for(lambda: self.avatars(status='failed')), 'PC 가 새 행을 실패로 바꾸지 않았다')
            return said(**{'sheet_body': paid_body(37), 'toast_seen': True, 'pill_enabled': True, 'generating_gone': True,
                           'regen_state': 'failed', 'regen_error': None, **over})
        return answer


def keep(*rows):
    return [{'keep': r['id']} for r in rows]


# ── 묶음 등록 · 앱 쪽 약속 ───────────────────────────────────────────────────────────────────────────

class RegistryTest(unittest.TestCase):
    def test_bundle_is_the_nine_in_the_order_of_the_scenario(self):
        self.assertEqual(area1.BUNDLES['area5-photo'], BUNDLE)
        self.assertEqual(list(area5_photo.PHONE), BUNDLE)
        self.assertLessEqual(set(BUNDLE), set(area1.PHONE))

    def test_the_runner_sees_the_bundle(self):
        probe = 'from e2e import __main__ as m, area1; print(m.BUNDLES.get("area5-photo"), "E-ME-44" in area1.PHONE)'
        out = subprocess.run([sys.executable, '-c', probe], cwd=tools.ROOT, capture_output=True, text=True, check=True).stdout
        self.assertEqual(out.strip(), f'{BUNDLE} True')

    def test_the_sixteen_of_the_first_c_bundle_are_not_repeated_or_changed(self):
        self.assertEqual(len(area1.BUNDLES['area5-act']), 16)
        self.assertEqual(set(BUNDLE) & set(area1.BUNDLES['area5-act']), set())
        self.assertEqual(set(BUNDLE) & set(area5_act.PHONE), set())

    def test_the_paid_case_is_wrapped_in_the_real_ai_gate_and_the_others_are_not(self):
        # _paid_case 가 감싼 함수는 이름이 case — 감싸지 않은 함수는 p_me_NN 이다.
        for name, function in area5_photo.PHONE.items():
            with self.subTest(name):
                self.assertEqual(function.__name__ == 'case', name in PAID)

    def test_the_watch_looks_at_least_twice_a_second(self):
        self.assertLessEqual(area5_photo.FLIP_POLL, 0.5)  # 워커가 행을 읽기 전에 바꾸려면 촘촘해야 한다

    def test_the_paid_case_gets_a_long_enough_time_limit(self):
        self.assertGreaterEqual(tools.CASE_LIMITS['E-ME-14'], 600)  # 앱이 90초까지 실패 안내를 기다린다


def app_dart():
    return dart('area5_photo.dart')


class AppContractTest(unittest.TestCase):
    """PC 가 읽는 앱 Map 키와 앱이 만드는 키가 한 글자도 다르지 않은지(양쪽으로) — 오타 한 글자는 늘 FAIL 이라 기계로 맞댄다."""

    def pc_keys(self):
        tree = ast.parse(Path(area5_photo.__file__).read_text(encoding='utf-8'))
        read = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == 'get' \
                    and isinstance(node.func.value, ast.Name) and node.func.value.id in ('said', 'row') \
                    and node.args and isinstance(node.args[0], ast.Constant) and isinstance(node.args[0].value, str):
                read.add(node.args[0].value)
        return read

    def test_the_app_registers_the_same_nine_cases(self):
        keys = re.findall(r"^\s*'(E-[A-Z]+-\d+)':", app_dart(), re.M)
        self.assertEqual(keys, BUNDLE)

    def test_area5_dart_only_adds_the_part_the_spread_and_the_imports_the_new_file_needs(self):
        text = dart('area5.dart')
        self.assertIn("part 'area5_photo.dart';", text)
        self.assertIn('...area5CasesPhoto', text)

    def test_the_keys_the_pc_reads_are_exactly_the_keys_the_app_says(self):
        said_keys = set(re.findall(r"'(\w+)':", app_dart()))
        read = self.pc_keys()
        self.assertGreater(len(read), 25)  # 읽는 키를 못 찾았다면 이 시험이 빈 껍데기다
        self.assertEqual(sorted(read - said_keys), [], '앱이 말하지 않는 키를 PC 가 읽는다')
        self.assertEqual(sorted(said_keys - read), [], 'PC 가 읽지 않는 키를 앱이 말한다')

    def test_every_key_the_app_reads_from_the_job_is_one_the_pc_sends_and_the_reverse(self):
        wanted = set(re.findall(r"job\['(\w+)'\]", app_dart()))
        tree = ast.parse(Path(area5_photo.__file__).read_text(encoding='utf-8'))
        sent = {kw.arg for node in ast.walk(tree) if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                and node.func.id == 'phone' for kw in node.keywords if kw.arg}
        self.assertEqual(sorted(wanted - sent), [])
        self.assertEqual(sorted(sent - wanted - {'midway', 'token_hash'}), [])
        self.assertGreater(len(sent), 4)

    def test_the_app_side_has_no_way_to_tap_the_delete_buttons(self):
        # 이 파일에서 `button(…)` 으로 눌러도 되는 라벨은 `_photoSave` 하나뿐이다.
        found = [(kind, line) for kind, line in delete_button_violations(app_dart())
                 if not (kind == 'b2' and set(re.findall(r'\bbutton\(([^()]*)\)', line)) == {'_photoSave'})]
        self.assertEqual(found, [])
        probe = app_dart() + '\nvoid probe() {\n  tap(tester, button(_somethingElse));\n}\n'
        self.assertTrue([1 for kind, line in delete_button_violations(probe) if kind == 'b2' and '_somethingElse' in line])

    def test_the_app_never_taps_a_wide_widget_by_its_type(self):
        # 가로 꽉 찬 위젯의 가운데는 빈 자리일 수 있다(#282) — 누르기는 글자 · 아이콘 · 버튼 안의 글자다.
        code = '\n'.join(re.sub(r'//.*$', '', line) for line in app_dart().split('\n'))
        self.assertNotRegex(code, r'tester\.tap\(find\.byType')
        self.assertNotRegex(code, r'\btap\(tester, find\.byType')

    def test_the_literals_the_app_looks_for_are_in_the_real_screens(self):
        screens = '\n'.join(path.read_text(encoding='utf-8') for path in (tools.ROOT / 'frontend' / 'lib').rglob('*.dart'))
        for literal in ('저장', '사진 수정', '실제 사진 교체', '다시 만들기 · 10', '하트 충전하기', '구매하기', '하트가 모자라요', '지금 보유한 하트는',
                        '사진은 최대 $_maxPhotos장까지 올릴 수 있어요', '얼굴이 보이는 사진을 골라 주세요', '$rejected장은 얼굴이 보이지 않아 빠졌어요',
                        '아바타로 변환 중이에요', '아바타를 다시 만들까요?', '프로필 편집'):
            with self.subTest(literal):
                self.assertTrue(literal in screens, f'{literal!r} 가 frontend/lib 에 없다')
        self.assertIn("'$cost 쓰고 만들기'", screens)  # 시트 CTA — 10 은 서버 값이라 템플릿이다
        self.assertIn("'아바타를 만들지 못했어요.\\n하트는 차감되지 않았어요.'", screens)
        self.assertIn(f'PHOTOS_CHANGED = "{CHANGED}"', (ROOT / 'core' / 'errors.py').read_text(encoding='utf-8'))
        # 안내 두 개(NONE_KEPT · ONE_DROPPED)는 앱이 글자를 들고 찾지 않는다 — 뷰모델의 errorMessage 를 그대로 말하고 PC 가 견준다.
        for literal in ('저장', '10 쓰고 만들기', '하트 충전하기', '구매하기', '하트', '하트가 모자라요', CHANGED, MAX_NOTICE, '아바타로 변환 중이에요', '사진 수정', '프로필 편집'):
            with self.subTest('app ' + literal):
                self.assertTrue(f"'{literal}'" in app_dart(), f'{literal!r} 가 area5_photo.dart 에 없다')
        self.assertTrue("'아바타를 만들지 못했어요.\\n하트는 차감되지 않았어요.'" in app_dart())

    def test_the_regen_pick_step_names_the_same_photo_and_button_as_the_pc_and_the_real_screen(self):
        # 알약 → 사진 고르기 걸음(regen_pick.dart)은 PC 가 앱 캐시에 넣는 파일 · 실제 15b-5 의 버튼 글자 · 갤러리 훅 공급자를 그대로 쓴다.
        step = dart('regen_pick.dart')
        pc = (tools.ROOT / 'e2e' / 'area1_b3.py').read_text(encoding='utf-8')
        self.assertIn("const regenPhotoName = 'face1.jpg';", step)
        self.assertIn("REGEN_PHOTO = 'face1.jpg'", pc)
        cta = re.search(r"const regenPickCta = '([^']+)';", step).group(1)
        self.assertIn(f"label: '{cta}'", lib('me', 'view', 'avatar_regen_pick_screen.dart'))
        self.assertIn('avatarRegenPickViewModelProvider.notifier).pickFromGallery', step)  # 다른 공급자의 훅이 아니다
        self.assertIn('AddPhotoTile(onTap: viewModel.pick)', lib('me', 'view', 'avatar_regen_pick_screen.dart'))  # 빈 칸의 + 아이콘을 누른다
        self.assertIn('AppIcons.plus', lib('profile', 'view', 'photo_tiles.dart'))
        self.assertIn("import 'regen_pick.dart';", dart('area5.dart'))
        self.assertIn("import 'regen_pick.dart';", dart('area2_c.dart'))

    def test_the_screens_say_the_same_numbers(self):
        # 15-7 의 2~4장 · 저장 규칙 / 끌기 / 갤러리 안내 — 시험이 기대하는 숫자가 지금 코드의 숫자다.
        self.assertIn('photos.length >= 2 && photos.length <= 4', lib('profile', 'viewmodel', 'photos_ui_state.dart'))
        # 화면 쪽 상수는 PhotosUiState.maxPhotos 하나를 보고, 그 숫자가 4 다(임시 저장 커밋 bace611e 이후).
        self.assertIn('const _maxPhotos = PhotosUiState.maxPhotos;', lib('profile', 'viewmodel', 'photos_view_model.dart'))
        self.assertIn('static const int maxPhotos = 4;', lib('profile', 'viewmodel', 'photos_ui_state.dart'))
        self.assertIn('MIN_PHOTOS, MAX_PHOTOS = 2, 4', (ROOT / 'me' / 'photo_layout.py').read_text(encoding='utf-8'))
        tiles = lib('profile', 'view', 'photo_tiles.dart')
        self.assertIn('LongPressDraggable<String>', tiles)
        self.assertIn('class DraggablePhotoTile', tiles)
        self.assertIn('AppIcons.plus', tiles)
        self.assertIn('AppIcons.x', tiles)
        self.assertIn('Duration duration = Duration(seconds: 2)', lib('me', 'view', 'me_toast.dart'))
        self.assertIn('myPhotosViewModelProvider', lib('me', 'view', 'my_photos_screen.dart'))  # 갤러리 훅은 이 공급자의 것이다(04-2 의 photosViewModelProvider 가 아니다)


# ── 서버 규칙: 가짜가 진짜 서버를 따라가는지 ──────────────────────────────────────────────────────────

def real_layout():
    sys.path.insert(0, str(tools.ROOT / 'backend'))
    try:
        from app.me.photo_layout import parse_layout
    except Exception:  # noqa: BLE001
        return None
    finally:
        sys.path.pop(0)
    return parse_layout


class ServerRulesTest(PhotoBase):
    def test_the_fake_layout_rule_is_the_real_one_for_good_and_bad_layouts(self):
        parse = real_layout()
        if parse is None:
            self.skipTest('백엔드 모듈을 들여올 수 없는 파이썬')
        cases = [('[{"keep":"a"},{"keep":"b"}]', 0, 0), ('[{"keep":"a"}]', 0, 0), ('[{"keep":"a"},{"keep":"b"},{"keep":"c"},{"keep":"d"},{"keep":"e"}]', 0, 0),
                 ('[{"keep":"a"},{"new":0}]', 1, 1), ('[{"keep":"a"},{"new":1}]', 1, 0), ('[{"keep":"a"},{"keep":"a"}]', 0, 0),
                 ('[{"keep":"a"},{"new":true}]', 1, 0), ('[{"keep":"a"},{"keep":"b"}]', 0, 2), ('[{"keep":"a"},{"keep":"b"}]', 0, -1),
                 ('not json', 0, 0), ('{}', 0, 0), ('[{"keep":1},{"keep":"b"}]', 0, 0), ('[{"keep":"a","new":0},{"keep":"b"}]', 0, 0),
                 ('[{"keep":"a"},{"keep":"b"},{"keep":"c"},{"keep":"d"}]', 0, 3)]
        for raw, new, source in cases:
            with self.subTest(raw, source=source):
                try:
                    want = parse(raw, new_count=new, avatar_source=source)
                except ValueError:
                    want = ValueError
                try:
                    got = parse_slots(raw, new, source)
                except ValueError:
                    got = ValueError
                self.assertEqual(got, want)

    def test_the_server_answers_with_the_texts_the_module_looks_for(self):
        errors = (ROOT / 'core' / 'errors.py').read_text(encoding='utf-8')
        for name, text in (('HEARTS_NOT_ENOUGH', LOW_TITLE), ('PHOTOS_CHANGED', CHANGED), ('PHOTO_NOT_SAFE', NOT_SAFE), ('INVALID_INPUT', INVALID)):
            with self.subTest(name):
                self.assertIn(f'{name} = "{text}"', errors)
        self.assertEqual(area5_photo.CHANGED, CHANGED)
        self.assertEqual(area5_photo.INVALID, INVALID)

    def test_the_fake_answers_have_the_keys_of_the_real_server(self):
        self.assertEqual(sorted(server_keys('profile_onboarding/router.py', '_avatar_status')), ['avatar_url', 'compensation_hearts', 'status'])
        router = (ROOT / 'me' / 'router.py').read_text(encoding='utf-8')
        self.assertIn('return {"ok": True}', router.split('async def save_photos')[1].split('@router.patch')[0])
        self.assertIn('"photos": [', router)
        self.assertIn('{"id": p["id"], "url": url, "is_avatar_source": p["is_avatar_source"]}', router)

    def test_the_fake_regenerate_follows_the_order_of_the_real_one(self):
        # 설정 → ready 0 (409) → 원본 없음 (409) → 하트 (402) → 큐 등록 (202)
        router = (ROOT / 'me' / 'router.py').read_text(encoding='utf-8').split('async def regenerate_avatar')[1].split('@router.put')[0]
        order = [router.index(word) for word in ('AVATAR_QUEUE_UNAVAILABLE', 'AVATAR_NOT_CREATED', 'AVATAR_SOURCE_REQUIRED', 'HEARTS_NOT_ENOUGH', 'enqueue_avatar_attempt(')]
        self.assertEqual(order, sorted(order))

    def test_the_grant_rpc_the_module_calls_has_the_arguments_the_fake_reads(self):
        migration = (tools.ROOT / 'supabase' / 'migrations' / '20260928020000_fix_grant_hearts_spend.sql').read_text(encoding='utf-8')
        self.assertIn('p_profile_id uuid, p_amount integer, p_reason public.heart_reason, p_ref_id uuid', migration)
        self.assertIn('amount <> 0', (tools.ROOT / 'supabase' / 'migrations' / '20260920043832_create_heart_ledger.sql').read_text(encoding='utf-8'))


# ── 유료 호출 · 디스코드: 서버 코드가 지금도 그 모양인지 ─────────────────────────────────────────────────

class PaidFactsTest(unittest.TestCase):
    """이 묶음의 유료 호출 표(area5_photo 의 docstring)가 기대는 서버 코드의 모양 — 코드가 바뀌면 표를 다시 쓰게 여기서 걸린다."""

    def text(self, *parts):
        return (ROOT.joinpath(*parts)).read_text(encoding='utf-8')

    def test_regenerate_ends_at_402_before_it_queues_anything(self):
        router = self.text('me', 'router.py').split('async def regenerate_avatar')[1].split('@router.put')[0]
        self.assertLess(router.index('errors.HEARTS_NOT_ENOUGH'), router.index('enqueue_avatar_attempt('))
        self.assertEqual(router.count('enqueue_avatar_attempt('), 1)

    def test_only_the_queue_registration_reaches_the_worker_and_the_worker_skips_before_openai(self):
        tasks = self.text('profile_onboarding', 'tasks_router.py')
        self.assertLess(tasks.index('attempt["status"] != "pending"'), tasks.index('AvatarGenerator('))
        self.assertLess(tasks.index('if updated == 0:'), tasks.index('await _charge_regeneration('))  # 실패로 바뀐 행은 하트도 안 뺀다
        self.assertIn('"status": "eq.pending"', self.text('profile_onboarding', 'repository.py').split('async def update_avatar_attempt')[1].split('async def')[0])

    def test_the_photo_save_calls_vision_once_per_new_file_and_never_before_the_layout_and_owner_checks(self):
        save = self.text('me', 'router.py').split('async def save_photos')[1].split('@router.patch')[0]
        self.assertEqual(save.count('check_safe_search('), 1)
        self.assertLess(save.index('parse_layout('), save.index('errors.PHOTOS_CHANGED'))
        self.assertLess(save.index('errors.PHOTOS_CHANGED'), save.index('for photo in photos:'))
        self.assertLess(save.index('for photo in photos:'), save.index('check_safe_search('))

    def test_these_paths_never_reach_the_discord_channels(self):
        for parts in (('me', 'router.py'), ('profile_onboarding', 'tasks_router.py'), ('profile_onboarding', 'router.py'), ('profile_onboarding', 'avatars.py'),
                      ('me', 'photo_layout.py'), ('me', 'repository.py')):
            with self.subTest(parts):
                text = self.text(*parts).lower()
                self.assertNotIn('discord', text)
                for route in ('/reports', '/student-verification', '/heart-tasks'):
                    self.assertNotIn(route, text)

    def test_the_account_factory_only_walks_the_onboarding_and_never_the_three_discord_routes(self):
        factory = (tools.ROOT / 'e2e' / 'tools.py').read_text(encoding='utf-8')
        for route in ('/reports', '/student-verification', '/heart-tasks'):
            self.assertNotIn(route, factory)


# ── 유료 문(E-ME-14) ────────────────────────────────────────────────────────────────────────────────

class PaidGateTest(PhotoBase):
    def case14(self, answer=None):
        return self.case('E-ME-14', None, self.midway(answer or self.good_14(), 'ready'))

    def test_without_the_env_var_not_one_request_goes_out_and_no_account_is_made(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            (result, note), app = self.case14()
        self.assertEqual(result, 'blocked')
        self.assertIn('E2E_REAL_AI', note)
        self.assertEqual(self.fake.sent, [])
        self.assertEqual(self.options, [])
        self.assertEqual(app.jobs, [])

    def test_the_other_eight_do_not_need_the_env_var(self):
        for name in [c for c in BUNDLE if c not in PAID]:
            with self.subTest(name), mock.patch.dict(os.environ, {}, clear=True):
                (result, note), _ = self.case(name, said())
                self.assertNotIn('E2E_REAL_AI', note)

    def test_a_failed_paid_case_gives_the_same_fail_and_does_not_start_the_app_again(self):
        answer = self.good_14(toast_seen=False)
        app = self.midway(answer, 'ready')
        (first, note), _ = self.case('E-ME-14', None, app)
        self.assertEqual(first, 'fail', note)
        self.assertIn('15-3', note)
        (second, again), _ = self.case('E-ME-14', None, app)
        self.assertEqual(second, 'fail')
        self.assertIn('유료 호출 뒤라 다시 하지 않음', again)
        self.assertEqual(len(app.jobs), 1)  # 앱을 두 번 켜지 않았다
        self.assertEqual(self.fake.sent, [])  # 계정도 요청도 다시 만들지 않았다(case 는 부르기 전에 기록을 비운다)

    def test_a_blocked_paid_case_is_not_run_again(self):
        app = self.midway({'result': 'blocked', 'note': '못 찾음'}, 'ready')
        (first, _), _ = self.case('E-ME-14', None, app)
        self.assertEqual(first, 'blocked')
        (second, note), _ = self.case('E-ME-14', None, app)
        self.assertEqual(second, 'blocked')
        self.assertIn('재시도 안 함', note)
        self.assertEqual(len(app.jobs), 1)

    def test_a_setup_failure_before_the_app_starts_is_not_marked_as_paid(self):
        self.second_avatar(Reply(500, {'message': 'down'}))
        (result, note), app = self.case14()
        self.assertEqual(result, 'blocked')
        self.assertIn('아바타 행 넣기', note)
        self.assertNotIn('E-ME-14', _PAID)  # 비용이 나가기 전의 막힘이라 다음에 다시 돌 수 있다
        self.assertEqual(app.jobs, [])

    def test_a_pass_is_remembered_so_a_second_call_does_not_pay_again(self):
        (result, note), _ = self.case14()
        self.assertEqual(result, 'pass', note)
        self.assertEqual(_PAID['E-ME-14'][0], 'pass')
        (second, again), app = self.case14()
        self.assertEqual(second, 'blocked')
        self.assertIn('재시도 안 함', again)


# ── E-ME-12 하트 모자람 시트 ────────────────────────────────────────────────────────────────────────

class LowHeartsSheetTest(PhotoBase):
    def good(self, **over):
        return as_fn(said(**{'sheet_title': LOW_TITLE, 'sheet_body': LOW_BODY, 'sheet_closed': True, 'store_seen': True, 'store_title': 1,
                             'regen_state': 'idle', **over}))

    def test_12_charge_closes_the_sheet_opens_the_heart_store_and_sends_nothing(self):
        note, app = self.passes('E-ME-12', self.good())
        self.assertEqual(app.jobs, [{'token_hash': 'h'}])
        self.assertEqual(self.fake.by('POST', '/me/avatar/regenerate'), [])  # 시트가 서버를 부르지 않는다
        self.assertEqual(self.fake.balance(), 5)
        self.assertEqual(len(self.avatars(status='ready')), 2)  # 15b 가 하트 줄을 보이는 조건(ready 2장 이상)
        self.assertEqual(len(self.avatars()), 2)
        self.assertEqual(self.fake.queued, 0)

    def test_12_the_photos_stay_as_they_were_and_the_regen_photo_was_pushed_first(self):
        seen = {}
        good = self.good()

        def answer(job):
            seen['before'] = [(r['id'], r['storage_path']) for r in self.photos()]  # 계정이 만들어진 뒤 · 앱이 아무것도 하기 전
            return good(job)
        self.adb_calls.clear()
        self.passes('E-ME-12', answer)
        self.assertEqual(len(seen['before']), 2)
        self.assertEqual([(r['id'], r['storage_path']) for r in self.photos()], seen['before'])
        self.assertEqual(self.fake.vision_calls, 0)
        self.assertEqual(self.pushed_regen_photo(), ['face1.jpg'])

    def test_12_fails_when_the_app_replaced_a_photo_though_the_sheet_should_have_stopped_it(self):
        def replaced(job):
            self.app_replace_source()
            return self.good()(job)
        self.fails('E-ME-12', replaced, '사진 행')

    def test_12_the_hearts_are_set_to_exactly_five_whatever_the_account_started_with(self):
        for starter, ledger in ((0, [5]), (5, []), (12, [-7])):
            with self.subTest(starter):
                self.fake.starter = starter
                self.passes('E-ME-12', self.good())
                self.assertEqual(self.fake.balance(), 5)
                self.assertEqual([r['amount'] for r in self.rows('heart_transactions')], ledger)
        self.assertEqual({r['reason'] for r in self.rows('heart_transactions')}, {'admin_adjust'})  # 12 → 5 는 원장 이유 avatar_regen 이 아니다

    def test_12_fails_on_each_wrong_sheet_store_or_state(self):
        for over, word in (({'sheet_title': PAID_TITLE}, '시트 제목'), ({'sheet_title': None}, '시트 제목'), ({'sheet_body': paid_body(5)}, '시트 글'),
                           ({'sheet_closed': False}, '시트 닫힘'), ({'store_seen': False}, '구매하기'), ({'store_seen': None}, '구매하기'),
                           ({'store_title': 0}, '앱바 제목'), ({'store_title': 2}, '앱바 제목'), ({'store_title': None}, '앱바 제목'),
                           ({'regen_state': 'failed'}, '다시 만들기를 불렀다')):
            with self.subTest(over):
                self.fails('E-ME-12', self.good(**over), word)

    def test_12_fails_when_the_app_says_nothing(self):
        self.fails('E-ME-12', lambda job: None, '답하지 않음')

    def test_12_fails_when_the_app_changed_the_avatars_the_hearts_or_the_ledger(self):
        def queued(job):
            self.fake.checks_hearts = False  # 하트가 모자라도 받아 주는 서버가 새 행을 만든다
            self.call_regenerate()
            return self.good()(job)

        def spent(job):
            self.fake.rows('entitlements')[0]['heart_balance'] = 0
            return self.good()(job)

        def ledgered(job):
            self.fake.rows('heart_transactions').append({'profile_id': 'id-1', 'amount': -10, 'reason': 'avatar_regen'})
            return self.good()(job)
        for answer, word in ((queued, '아바타'), (spent, '하트'), (ledgered, '원장')):
            with self.subTest(word):
                self.fails('E-ME-12', answer, word)

    def test_12_is_blocked_when_the_second_avatar_cannot_be_added_or_the_hearts_cannot_be_set(self):
        self.second_avatar(Reply(500, {'message': 'down'}))
        self.blocked('E-ME-12', self.good(), '아바타 행 넣기')
        self.fake.handlers.pop(0)
        self.fake.starter = 0
        self.swallow('POST', r'/rest/v1/rpc/grant_hearts')
        self.blocked('E-ME-12', self.good(), '준비', '하트')

    def test_12_is_blocked_with_the_reason_when_the_hearts_write_is_refused(self):
        self.fake.starter = 0
        self.fake.handlers.insert(0, ('POST', re.compile(r'/rest/v1/rpc/grant_hearts'), Reply(500, {'message': 'down'})))
        self.blocked('E-ME-12', self.good(), '준비', '쓰기 500')

    def test_12_is_blocked_when_the_ready_count_is_not_two(self):
        self.swallow('POST', r'/rest/v1/profile_avatars')  # 더하는 척만 하고 안 더한다
        self.blocked('E-ME-12', self.good(), '준비', '2장')

    def test_12_writes_only_to_the_account_it_made(self):
        self.case('E-ME-12', self.good())
        self.writes_only_mine()


# ── E-ME-13 열어 둔 사이 잔액이 줄면 402 ─────────────────────────────────────────────────────────────

class StaleBalanceTest(PhotoBase):
    def good(self, **over):
        def answer(job):
            self.app_replace_source()  # 사진 교체가 먼저 성공하고
            reply = self.call_regenerate()  # 앱의 "10 쓰고 만들기" — PC 가 하트를 낮춘 뒤에 눌렀다
            self.status_seen = reply[0]
            return said(**{'sheet_title': PAID_TITLE, 'sheet_body': paid_body(37), 'caption_seen': True, 'on_pick_screen': True,
                           'regen_state': 'failed', 'regen_error': LOW_TITLE, **over})
        return answer

    def run13(self, answer=None):
        return self.case('E-ME-13', None, self.midway(answer or self.good(), 'opened'))

    def test_13_the_hearts_drop_to_five_while_the_screen_still_holds_37_and_the_server_says_402(self):
        (result, note), app = self.run13()
        self.assertEqual(result, 'pass', note)
        self.assertEqual(self.status_seen, 402)
        self.assertEqual(self.events, ['step', 'go'])  # 앱이 연 뒤 멈추고 PC 가 일한 뒤 이어 갔다
        self.assertEqual(app.jobs, [{'token_hash': 'h'}])
        self.assertEqual(self.fake.balance(), 5)
        self.assertEqual(self.ledger('avatar_regen'), [])
        self.assertEqual(len(self.avatars()), 2)  # 새 pending 행 0
        self.assertEqual(self.fake.queued, 0)  # 큐에 안 넣었다
        self.assertEqual([r['amount'] for r in self.rows('heart_transactions')], [32, -32])  # 처음 5 → 37 로 올리고 → 5 로 낮춘다

    def test_13_the_new_photo_is_already_the_source_when_the_402_comes_and_that_is_part_of_the_verdict(self):
        # 사진 교체(성공) 뒤 등록이 402 — 새 사진은 원본으로 남는다(서버가 두 요청이라는 한계). 사진 목록 장수는 그대로, 원본 칸만 새 파일.
        seen = {}
        good = self.good()

        def answer(job):
            seen['before'] = [(r['id'], r['storage_path']) for r in self.photos()]
            return good(job)
        (result, note), _ = self.run13(answer)
        self.assertEqual(result, 'pass', note)
        before, now = seen['before'], self.photos()
        self.assertEqual(len(now), len(before))
        self.assertEqual(sum(1 for r in now if r['is_avatar_source']), 1)
        self.assertEqual(len({r['storage_path'] for r in now} - {path for _, path in before}), 1)
        self.assertIn('원본', note)
        self.assertEqual(self.fake.vision_calls, 1)  # 사진 교체가 Vision 을 한 번 불렀다

    def test_13_fails_when_the_photo_was_not_replaced_before_the_402(self):
        def skipped(job):
            reply = self.call_regenerate()  # 사진 교체 없이 등록만 — 하트 부족 402 로 끝나는 옛 흐름
            self.status_seen = reply[0]
            return said(sheet_title=PAID_TITLE, sheet_body=paid_body(37), caption_seen=True, on_pick_screen=True, regen_state='failed', regen_error=LOW_TITLE)
        (result, note), _ = self.run13(skipped)
        self.assertEqual(result, 'fail', note)
        self.assertIn('원본 칸', note)

    def test_13_the_lowering_is_a_write_in_the_ledger_with_an_admin_reason_not_an_avatar_regen(self):
        self.run13()
        self.assertEqual({r['reason'] for r in self.rows('heart_transactions')}, {'free_task', 'admin_adjust'})

    def test_13_fails_on_each_wrong_sheet_toast_or_state(self):
        for over, word in (({'sheet_title': LOW_TITLE}, '시트 제목'), ({'sheet_body': paid_body(5)}, '낡은'), ({'sheet_body': LOW_BODY}, '낡은'),
                           ({'caption_seen': False}, '문구'), ({'on_pick_screen': False}, '사진 고르기'), ({'on_pick_screen': None}, '사진 고르기'),
                           ({'regen_state': 'idle'}, '다시 만들기'), ({'regen_error': None}, '서버 문구'), ({'regen_error': '다른 문구'}, '서버 문구')):
            with self.subTest(over):
                self.reset_paid()
                (result, note), _ = self.run13(self.good(**over))
                self.assertEqual(result, 'fail', note)
                self.assertIn(word, note)

    def test_13_fails_when_the_server_queues_the_work_instead_of_answering_402(self):
        # 하트 계산이 어긋난 서버 — 202 가 되면 그 요청이 곧 유료 AI 호출이다.
        self.fake.checks_hearts = False
        (result, note), _ = self.run13()
        self.assertEqual(result, 'fail', note)
        self.assertIn('큐', note)
        self.assertIn('유료', note)
        self.assertEqual(self.fake.queued, 1)

    def test_13_fails_when_the_hearts_or_the_ledger_moved_after_the_press(self):
        def spends(job):
            answer = self.good()(job)
            self.fake.rows('entitlements')[0]['heart_balance'] = 0
            return answer

        def ledgers(job):
            answer = self.good()(job)
            self.fake.rows('heart_transactions').append({'profile_id': 'id-1', 'amount': -10, 'reason': 'avatar_regen'})
            return answer
        for answer, word in ((spends, '하트'), (ledgers, '원장')):
            with self.subTest(word):
                self.reset_paid()
                (result, note), _ = self.run13(answer)
                self.assertEqual(result, 'fail', note)
                self.assertIn(word, note)

    def test_13_is_blocked_when_the_lowering_did_nothing(self):
        # 낮추지 못했는데 앱이 눌러 버리면 그 요청이 곧 유료 호출이다 — 멈춘 사이에 읽어 보고 막는다.
        self.swallow('POST', r'/rest/v1/rpc/grant_hearts')
        self.fake.starter = 37
        (result, note), _ = self.run13()
        self.assertEqual(result, 'blocked', note)
        self.assertIn('하트', note)

    def test_13_writes_only_to_the_account_it_made(self):
        self.run13()
        self.writes_only_mine()


# ── E-ME-14 실패하면 하트가 안 빠지고 15-3 토스트 ────────────────────────────────────────────────────

class FailedRegenerateTest(PhotoBase):
    def good(self, **over):
        return self.good_14(**over)

    def run14(self, answer=None):
        return self.case('E-ME-14', None, self.midway(answer or self.good(), 'ready'))

    def test_14_the_new_pending_row_is_failed_at_once_and_nothing_is_charged(self):
        (result, note), app = self.run14()
        self.assertEqual(result, 'pass', note)
        self.assertEqual(sorted(self.regen_reply[1]), sorted(server_keys('profile_onboarding/router.py', '_avatar_status')))  # 202 본문 칸
        self.assertIn('OpenAI', note)  # 유료 호출이 남을 수 있다는 한 줄이 메모에 있다
        self.assertEqual(app.jobs, [{'token_hash': 'h'}])
        self.assertEqual(self.fake.balance(), 37)
        self.assertEqual(self.ledger('avatar_regen'), [])
        self.assertEqual(sorted(a['status'] for a in self.avatars()), ['failed', 'ready', 'ready'])
        self.assertEqual(self.fake.queued, 1)  # 앱이 한 번 눌렀다
        self.assertEqual(len(self.fake.by('POST', '/me/avatar/regenerate')), 1)

    def test_14_only_a_pending_row_is_turned_into_failed_and_the_watch_stops_after_the_app_ends(self):
        before = threading.active_count()
        self.run14()
        patches = self.fake.by('PATCH', '/rest/v1/profile_avatars')
        self.assertEqual(len(patches), 1)
        self.assertEqual(patches[0]['query']['status'], 'eq.pending')  # ready 로 끝난 행을 되돌려 쓰지 않게
        self.assertEqual(patches[0]['body'], {'status': 'failed'})
        self.assertTrue(wait_for(lambda: threading.active_count() <= before), '지켜보는 줄기가 앱이 끝난 뒤에도 남음')

    def test_14_the_watch_starts_only_when_the_app_is_about_to_press(self):
        (result, _), _ = self.run14()
        self.assertEqual(self.events, ['step', 'go'])
        self.assertEqual(result, 'pass')

    def test_14_a_worker_that_finishes_first_makes_it_blocked_not_a_fail(self):
        self.fake.after_queue = lambda row: row.update(status='ready', storage_path='id-1/new.png')  # 큐에 넣자마자 워커가 끝냈다
        (result, note), _ = self.run14(lambda job: (self.call_regenerate(), said())[1])
        self.assertEqual(result, 'blocked', note)
        self.assertIn('워커', note)
        self.assertIn('유료', note)
        self.assertEqual(_PAID['E-ME-14'][0], 'blocked')  # 비용이 나갔다 — 다시 돌지 않는다

    def test_14_fails_on_each_wrong_toast_pill_or_state(self):
        for over, word in (({'toast_seen': False}, '15-3'), ({'pill_enabled': False}, '알약'), ({'generating_gone': False}, '변환 중'),
                           ({'regen_state': 'generating'}, '상태'), ({'regen_error': '하트가 모자라요'}, '서버 문구'), ({'sheet_body': paid_body(5)}, '시트 글')):
            with self.subTest(over):
                self.reset_paid()
                (result, note), _ = self.run14(self.good(**over))
                self.assertEqual(result, 'fail', note)
                self.assertIn(word, note)

    def test_14_fails_when_the_hearts_were_charged_or_the_ledger_has_an_avatar_regen_row(self):
        def charges(job):
            answer = self.good()(job)
            self.fake.rows('entitlements')[0]['heart_balance'] = 27
            return answer

        def ledgers(job):
            answer = self.good()(job)
            self.fake.rows('heart_transactions').append({'profile_id': 'id-1', 'amount': -10, 'reason': 'avatar_regen'})
            return answer
        for answer, word in ((charges, '하트'), (ledgers, '원장')):
            with self.subTest(word):
                self.reset_paid()
                (result, note), _ = self.run14(answer)
                self.assertEqual(result, 'fail', note)
                self.assertIn(word, note)

    def test_14_fails_when_no_new_avatar_row_ever_appeared(self):
        (result, note), _ = self.run14(lambda job: said(sheet_body=paid_body(37), toast_seen=True, pill_enabled=True, generating_gone=True,
                                                          regen_state='failed', regen_error=None))
        self.assertEqual(result, 'fail', note)
        self.assertIn('등록되지 않았다', note)

    def test_14_fails_when_a_second_new_avatar_row_appeared(self):
        def doubles(job):
            answer = self.good()(job)
            self.fake.rows('profile_avatars').append({'id': 'extra', 'profile_id': 'id-1', 'status': 'failed', 'storage_path': None, 'created_at': now().isoformat()})
            return answer
        (result, note), _ = self.run14(doubles)
        self.assertEqual(result, 'fail', note)
        self.assertIn('failed 1개', note)

    def test_14_fails_when_the_ready_avatars_changed(self):
        def eats(job):
            answer = self.good()(job)
            self.avatars(status='ready')[0]['status'] = 'failed'
            return answer
        (result, note), _ = self.run14(eats)
        self.assertEqual(result, 'fail', note)
        self.assertIn('완성', note)

    def test_14_is_blocked_when_the_flip_could_not_be_written(self):
        self.swallow('PATCH', r'/rest/v1/profile_avatars')
        (result, note), _ = self.run14(lambda job: (self.call_regenerate(), said())[1])
        self.assertEqual(result, 'blocked', note)
        self.assertIn('pending', note)

    def test_14_the_watch_is_really_stopped_when_finish_returns(self):
        # 줄기가 아직 읽는 중에 끝내면 기다렸다가 멈춘다 — 앱이 끝난 뒤에 몰래 쓰지 않게
        account = {'id': 'id-1'}
        watcher = area5_photo._Watcher(self.run_, account, set())
        watcher.seen = {'id': 'x'}  # 이미 본 것으로 두어 finish 의 마지막 한 번 읽기가 끼지 않게 한다
        with mock.patch.object(watcher, '_look', side_effect=lambda: (time.sleep(0.3), False)[1]):
            watcher.start()
            time.sleep(0.05)
            watcher.finish()
            self.assertFalse(watcher._thread.is_alive())

    def test_14_a_watch_that_crashes_is_blocked_with_the_reason(self):
        def breaks(job):
            # 지켜보기가 이미 돌고 있는 사이 읽기가 고장 난다 — 준비 단계의 읽기는 이미 끝났다
            self.fake.handlers.insert(0, ('GET', re.compile(r'/rest/v1/profile_avatars'), Reply(500, {'message': 'down'})))
            time.sleep(0.2)
            return said()
        (result, note), _ = self.run14(breaks)
        self.assertEqual(result, 'blocked', note)
        self.assertIn('지켜보기', note)

    def test_14_writes_only_to_the_account_it_made(self):
        self.run14()
        self.writes_only_mine()


# ── E-ME-10 · 11 · 16 워커가 새 아바타를 만든다(유료 AI) ────────────────────────────────────────────

class WorkerRegenTest(PhotoBase):
    """앱이 누르면 서버가 큐에 넣고 워커가 새 아바타를 만든다 — 시험이 워커를 흉내 낸다(pending → ready, 값이 있으면 하트 원장 -10 도)."""

    def worker(self, charge=0):
        row = self.avatars(status='pending')[0]
        row.update(status='ready', storage_path='id-1/new.png')
        if charge:
            self.fake.rows('entitlements')[0]['heart_balance'] -= charge
            self.fake.rows('heart_transactions').append({'profile_id': 'id-1', 'amount': -charge, 'reason': 'avatar_regen', 'ref_id': row['id']})
        return row

    def good(self, name, **over):
        def answer(job):
            self.app_replace_source()  # 사진 교체가 먼저(Vision 1번) — 지금 아바타 원본 칸만 새 사진으로
            self.assertEqual(self.call_regenerate()[0], 202)
            self.charged_row = self.worker(10 if name == 'E-ME-11' else 0)
            said_ = {'generating_seen': True, 'avatar_changed': True, 'generating_gone': True, 'regen_state': 'ready', 'waited_ms': 20000}
            if name == 'E-ME-10':
                said_.update(sheet_title=PAID_TITLE, sheet_texts=[PAID_TITLE, FREE_BODY, '무료로 만들기', '취소'])
            if name == 'E-ME-11':
                said_.update(sheet_title=PAID_TITLE, sheet_body=paid_body(37))
            if name == 'E-ME-16':
                said_.update(generating_after_return=True)
            return said(**{**said_, **over})
        return answer

    def run_case(self, name, answer=None):
        return self.case(name, answer or self.good(name))

    # ── 10 첫 다시 만들기는 무료 ──
    def test_10_the_first_regenerate_is_free_and_a_new_avatar_appears(self):
        (result, note), app = self.run_case('E-ME-10')
        self.assertEqual(result, 'pass', note)
        self.assertEqual(app.jobs, [{'token_hash': 'h'}])
        self.assertEqual(sorted(a['status'] for a in self.avatars()), ['ready', 'ready'])
        self.assertEqual(self.ledger('avatar_regen'), [])
        self.assertEqual(self.fake.queued, 1)
        self.assertEqual(self.fake.vision_calls, 1)  # 사진 교체의 SafeSearch 한 번
        self.assertEqual(self.pushed_regen_photo(), ['face1.jpg'])  # 앱이 갤러리에서 고를 사진을 계정을 만들기 전에 앱 캐시로 옮겼다

    def test_10_fails_on_a_charge_a_missing_free_text_a_heart_line_or_an_unchanged_picture(self):
        def charged(job):
            answer = self.good('E-ME-10')(job)
            self.fake.rows('entitlements')[0]['heart_balance'] -= 10
            return answer
        for answer, word in ((charged, '하트'),
                             (self.good('E-ME-10', sheet_texts=[PAID_TITLE, '하트 10개가 차감돼요. 지금 보유한 하트는 5개예요.', '10 쓰고 만들기', '취소']), '무료'),
                             (self.good('E-ME-10', avatar_changed=False), '그림'),
                             (self.good('E-ME-10', generating_seen=False), '변환 중'),
                             (self.good('E-ME-10', regen_state='failed'), '상태'),
                             (self.good('E-ME-10', waited_ms=700000), '10분')):
            with self.subTest(word):
                self.reset_paid()
                (result, note), _ = self.run_case('E-ME-10', answer)
                self.assertEqual(result, 'fail', note)
                self.assertIn(word, note)

    def test_10_fails_when_the_worker_never_made_a_ready_avatar(self):
        def stuck(job):
            self.app_replace_source()
            self.assertEqual(self.call_regenerate()[0], 202)
            return said(generating_seen=True, avatar_changed=True, generating_gone=True, regen_state='ready', waited_ms=1000,
                        sheet_title=PAID_TITLE, sheet_texts=[PAID_TITLE, FREE_BODY, '무료로 만들기', '취소'])
        (result, note), _ = self.run_case('E-ME-10', stuck)
        self.assertEqual(result, 'fail', note)
        self.assertIn('완성', note)

    def test_10_is_blocked_when_the_account_does_not_start_with_one_ready_avatar(self):
        # 2장이면 첫 다시 만들기가 무료가 아니다 — 준비가 조건을 못 맞추면 blocked 로 멈춘다(앱을 켜기 전에)
        with mock.patch.object(area5_photo, '_ready_avatars', return_value=[{}, {}]):
            (result, note), app = self.run_case('E-ME-10', said())
        self.assertEqual(result, 'blocked', note)
        self.assertEqual(app.jobs, [])

    # ── 11 두 번째부터 10개 ──
    def test_11_the_second_regenerate_costs_ten_after_completion_with_a_ledger_row_that_points_at_the_new_avatar(self):
        (result, note), app = self.run_case('E-ME-11')
        self.assertEqual(result, 'pass', note)
        self.assertEqual(self.fake.balance(), 27)
        self.assertEqual(self.ledger('avatar_regen'), [-10])
        ref = self.rows('heart_transactions', reason='avatar_regen')[0]['ref_id']
        self.assertEqual(ref, self.charged_row['id'])
        self.assertEqual(sorted(a['status'] for a in self.avatars()), ['ready', 'ready', 'ready'])

    def test_11_fails_on_a_wrong_balance_a_missing_or_double_ledger_or_a_ledger_without_ref(self):
        def uncharged(job):
            self.good('E-ME-11')(job)
            self.fake.rows('entitlements')[0]['heart_balance'] = 37
            self.fake.rows('heart_transactions').clear()
            return said(**{'generating_seen': True, 'avatar_changed': True, 'generating_gone': True, 'regen_state': 'ready', 'waited_ms': 1,
                           'sheet_title': PAID_TITLE, 'sheet_body': paid_body(37)})

        def doubled(job):
            answer = self.good('E-ME-11')(job)
            self.fake.rows('entitlements')[0]['heart_balance'] -= 10
            self.fake.rows('heart_transactions').append({'profile_id': 'id-1', 'amount': -10, 'reason': 'avatar_regen', 'ref_id': 'other'})
            return answer

        def no_ref(job):
            answer = self.good('E-ME-11')(job)
            self.fake.rows('heart_transactions')[-1]['ref_id'] = None
            return answer
        def wrong_ref(job):
            answer = self.good('E-ME-11')(job)
            self.fake.rows('heart_transactions')[-1]['ref_id'] = 'other'
            return answer
        for answer, word in ((uncharged, '하트'), (doubled, '원장'), (no_ref, 'ref_id'), (wrong_ref, '새 아바타 행')):
            with self.subTest(word):
                self.reset_paid()
                (result, note), _ = self.run_case('E-ME-11', answer)
                self.assertEqual(result, 'fail', note)
                self.assertIn(word, note)

    def test_11_fails_on_a_wrong_sheet_text(self):
        (result, note), _ = self.run_case('E-ME-11', self.good('E-ME-11', sheet_body=paid_body(5)))
        self.assertEqual(result, 'fail', note)
        self.assertIn('시트 글', note)

    # ── 16 만드는 중에 오늘 탭을 다녀옴 ──
    def test_16_leaving_to_the_today_tab_and_coming_back_keeps_waiting_and_the_new_avatar_appears(self):
        (result, note), _ = self.run_case('E-ME-16')
        self.assertEqual(result, 'pass', note)
        self.assertEqual(sorted(a['status'] for a in self.avatars()), ['ready', 'ready'])
        self.assertEqual(self.fake.queued, 1)

    def test_16_fails_when_the_wait_stopped_after_coming_back_or_no_new_avatar(self):
        for over, word in (({'generating_after_return': False}, '돌아'), ({'avatar_changed': False}, '그림'), ({'regen_state': 'idle'}, '상태')):
            with self.subTest(over):
                self.reset_paid()
                (result, note), _ = self.run_case('E-ME-16', self.good('E-ME-16', **over))
                self.assertEqual(result, 'fail', note)
                self.assertIn(word, note)

    # ── 셋 다 ──
    def test_the_three_fail_when_the_app_registered_without_replacing_the_source_photo(self):
        for name in ('E-ME-10', 'E-ME-11', 'E-ME-16'):
            with self.subTest(name):
                self.reset_paid()
                good = self.good(name)

                def no_replace(job, good=good):
                    with mock.patch.object(type(self), 'app_replace_source', lambda self_, *a, **k: None):
                        return good(job)
                (result, note), _ = self.run_case(name, no_replace)
                self.assertEqual(result, 'fail', note)
                self.assertIn('원본 칸', note)

    def test_the_three_push_the_regen_photo_before_the_account_is_made(self):
        for name in ('E-ME-10', 'E-ME-11', 'E-ME-16'):
            with self.subTest(name):
                self.reset_paid()
                self.adb_calls.clear()
                (result, note), _ = self.run_case(name)
                self.assertEqual(result, 'pass', note)
                self.assertEqual(self.pushed_regen_photo(), ['face1.jpg'])

    def test_every_regen_case_is_blocked_before_any_account_when_the_photo_set_lacks_face1(self):
        # 다시 만들기는 사진부터 고른다 — 앱 캐시에 옮길 face1.jpg 가 없으면 앱이 막히기 전에 PC 가 계정을 만들지 않고 blocked 로 끝낸다(E-ME-38 과 같다).
        (self.folder / 'face1.jpg').unlink()
        for name in ('E-ME-10', 'E-ME-11', 'E-ME-12', 'E-ME-13', 'E-ME-14', 'E-ME-16', 'E-ME-40'):
            with self.subTest(name):
                self.reset_paid()
                (result, note), app = self.case(name, said())
                self.assertEqual(result, 'blocked', note)
                self.assertIn('사진 세트 없음', note)
                self.assertIn('face1.jpg', note)
                self.assertEqual(self.fake.users, [])
                self.assertEqual(app.jobs, [])

    def test_the_three_are_behind_the_real_ai_gate_and_make_no_request_without_it(self):
        for name in ('E-ME-10', 'E-ME-11', 'E-ME-16'):
            with self.subTest(name), mock.patch.dict(os.environ, {}, clear=True):
                (result, note), app = self.run_case(name, said())
                self.assertEqual(result, 'blocked')
                self.assertIn('E2E_REAL_AI', note)
                self.assertEqual(self.fake.sent, [])
                self.assertEqual(app.jobs, [])

    def test_the_three_wait_for_the_worker_longer_than_the_default(self):
        for name in ('E-ME-10', 'E-ME-11', 'E-ME-16'):
            self.assertGreaterEqual(tools.CASE_LIMITS[name], 900)

    def test_the_three_write_only_to_the_account_they_made(self):
        for name in ('E-ME-10', 'E-ME-11', 'E-ME-16'):
            self.reset_paid()
            self.run_case(name)
            self.writes_only_mine()


# ── 15-7 사진 수정 ──────────────────────────────────────────────────────────────────────────────────

class SaveTest(PhotoBase):
    """E-ME-38 — 한 장 빼고 새 사진을 넣어 저장."""

    def good(self, **over):
        def answer(job):
            rows = self.photos()
            ids = [r['id'] for r in rows]
            before = [name_of(r) for r in rows]
            kept = [ids[0], ids[2], ids[3]]
            self.app_save([{'keep': i} for i in kept] + [{'new': 0}], 0, files=1)
            after = [name_of(r) for r in self.photos()]
            return said(**{'ids_open': ids, 'ids_removed': kept, 'ids_added': kept + [None], 'asked': [1], 'message': None, 'save_enabled': True,
                           'title': '프로필 편집', 'names_before': before, 'names_after': after, **over})
        return answer

    def test_38_one_removed_one_added_in_one_save_and_the_removed_file_is_gone_from_storage(self):
        note, app = self.passes('E-ME-38', self.good())
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'photo': 'face1.jpg'}])
        rows = self.photos()
        self.assertEqual([r['position'] for r in rows], [0, 1, 2, 3])
        self.assertEqual(self.fake.vision_calls, 1)  # 새 사진 한 장에 한 번
        self.assertEqual(self.files(), sorted(r['storage_path'] for r in rows))

    def test_38_the_photo_is_pushed_to_the_phone_once_before_the_app_starts(self):
        self.passes('E-ME-38', self.good())
        pushed = [c for c in self.adb_calls if 'push' in c]
        self.assertEqual(len(pushed), 1)
        self.assertTrue(pushed[0][2].endswith('face1.jpg'))

    def test_38_is_blocked_before_any_account_when_the_photo_set_lacks_the_file(self):
        (self.folder / 'face1.jpg').unlink()
        self.blocked('E-ME-38', self.good(), '사진 세트 없음', 'face1.jpg')
        self.assertEqual(self.fake.users, [])

    def test_38_fails_on_each_wrong_app_report(self):
        for over, word in (({'asked': [2]}, '남은 칸'), ({'asked': []}, '남은 칸'), ({'save_enabled': False}, '저장 버튼'), ({'title': '사진 수정'}, '저장 뒤 화면'),
                           ({'message': NONE_KEPT}, '안내'), ({'ids_removed': ['x']}, '뺀'), ({'ids_added': ['x']}, '넣은'),
                           ({'ids_open': ['9', '8', '7', '6']}, '열었을 때')):
            with self.subTest(over):
                self.fails('E-ME-38', self.good(**over), word)

    def test_38_fails_when_15_5_still_shows_the_old_photos(self):
        def stale(job):
            answer = self.good()(job)
            answer['names_after'] = answer['names_before']
            return answer
        self.fails('E-ME-38', stale, '15-5')

    def test_38_fails_when_the_removed_row_stays_the_order_is_wrong_or_a_position_has_a_hole(self):
        def removed_stays(job):
            gone = self.photos()[1]['id']
            answer = self.good()(job)
            self.fake.rows('profile_photos').append({'id': gone, 'profile_id': 'id-1', 'position': 3, 'is_avatar_source': False, 'storage_path': 'id-1/x.jpg'})
            return answer

        def new_first(job):
            answer = self.good()(job)
            for row in self.photos():
                row['position'] = (row['position'] + 1) % 4
            return answer

        def hole(job):
            answer = self.good()(job)
            self.photos()[-1]['position'] = 5
            return answer
        for answer, word in ((removed_stays, '4장'), (new_first, '순서'), (hole, '위치')):
            with self.subTest(word):
                self.fails('E-ME-38', answer, word)

    def test_38_fails_when_two_new_photos_were_saved_or_the_wrong_one_was_removed(self):
        def two_new(job):
            rows = self.photos()
            self.app_save([{'keep': rows[0]['id']}, {'keep': rows[2]['id']}, {'new': 0}, {'new': 1}], 0, files=2)
            return said(ids_open=[r['id'] for r in rows], ids_removed=[rows[0]['id'], rows[2]['id'], rows[3]['id']], ids_added=[], asked=[1], message=None,
                        save_enabled=True, title='프로필 편집', names_before=[name_of(r) for r in rows], names_after=[name_of(r) for r in self.photos()])
        self.fails('E-ME-38', two_new, '새 사진 행')

        def wrong_removed(job):
            rows = self.photos()
            self.app_save([{'keep': rows[0]['id']}, {'keep': rows[1]['id']}, {'keep': rows[2]['id']}, {'new': 0}], 0, files=1)
            return said(ids_open=[r['id'] for r in rows], ids_removed=[rows[0]['id'], rows[2]['id'], rows[3]['id']], ids_added=[], asked=[1], message=None,
                        save_enabled=True, title='프로필 편집', names_before=[name_of(r) for r in rows], names_after=[name_of(r) for r in self.photos()])
        self.fails('E-ME-38', wrong_removed, '뺀 사진 행')

    def test_38_fails_when_15_5_was_not_read_before_the_save(self):
        self.fails('E-ME-38', self.good(names_before=['x', 'y', 'z', 'w']), '저장 전')

    def test_38_fails_when_the_removed_file_is_still_in_the_bucket_or_the_new_file_is_not(self):
        self.fake.deletes_files = False
        self.fails('E-ME-38', self.good(), '저장소')
        self.fake.deletes_files = True

        def forgets(job):
            answer = self.good()(job)
            self.fake.storage['profile-photos'].discard(self.photos()[-1]['storage_path'])
            return answer
        self.fails('E-ME-38', forgets, '저장소')

    def test_38_fails_when_the_new_photo_was_not_saved_or_a_second_avatar_source_exists(self):
        def three(job):
            rows = self.photos()
            self.app_save(keep(rows[0], rows[2], rows[3]), 0)
            return said(ids_open=[r['id'] for r in rows], ids_removed=[rows[0]['id'], rows[2]['id'], rows[3]['id']],
                        ids_added=[rows[0]['id'], rows[2]['id'], rows[3]['id'], None], asked=[1], message=None, save_enabled=True, title='프로필 편집',
                        names_before=[name_of(r) for r in rows], names_after=[name_of(r) for r in self.photos()])
        self.fails('E-ME-38', three, '4장')

        def two_sources(job):
            answer = self.good()(job)
            for row in self.photos():
                row['is_avatar_source'] = True
            return answer
        self.fails('E-ME-38', two_sources, '아바타 원본')

    def test_38_a_photo_the_server_calls_unsafe_stays_on_15_7_and_is_a_fail(self):
        self.fake.unsafe = True

        def rejected(job):
            rows = self.photos()
            reply = self.app_save(keep(rows[0], rows[2], rows[3]) + [{'new': 0}], 0, files=1, expect=422)
            self.assertEqual(reply[1], {'detail': NOT_SAFE})
            return said(ids_open=[r['id'] for r in rows], title='사진 수정')
        self.fails('E-ME-38', rejected, '저장 뒤 화면')
        self.assertEqual(self.fake.vision_calls, 1)  # 부른 만큼 센다
        self.assertEqual(len(self.photos()), 4)

    def test_38_writes_only_to_the_account_it_made(self):
        self.case('E-ME-38', self.good())
        self.writes_only_mine()


class DragTest(PhotoBase):
    """E-ME-39 — 길게 눌러 끌어 순서를 바꾸면 첫 칸이 대표."""

    def good(self, via='drag', **over):
        def answer(job):
            rows = self.photos()
            ids = [r['id'] for r in rows]
            swapped = [ids[2], ids[1], ids[0]]
            self.app_save([{'keep': i} for i in swapped], 2)  # 대표(원본) 표시는 사진을 따라간다 — 처음 원본은 맨 앞 사진이었다
            return said(**{'ids_open': ids, 'ids_dragged': swapped, 'via': via, 'save_enabled': True, 'title': '프로필 편집',
                           'names_before': [name_of(r) for r in rows], 'names_after': [name_of(r) for r in self.photos()], **over})
        return answer

    def test_39_the_third_photo_dragged_to_the_first_slot_becomes_position_zero_and_15_5_shows_it_first(self):
        note, app = self.passes('E-ME-39', self.good())
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'drag': [2, 0]}])
        rows = self.photos()
        self.assertEqual([r['position'] for r in rows], [0, 1, 2])
        self.assertEqual(self.fake.vision_calls, 0)  # 새 파일이 없는 저장은 Vision 을 안 부른다
        self.assertEqual(self.files(), sorted(r['storage_path'] for r in rows))  # 파일은 그대로

    def test_39_a_drag_that_did_not_work_is_a_pass_with_the_substitute_named_in_the_note(self):
        note, _ = self.passes('E-ME-39', self.good(via='swap-call'))
        self.assertIn('끌기', note)
        self.assertIn('swapPhotos', note)
        self.assertIn('실기기', note)

    def test_39_a_drag_that_moved_the_wrong_photos_is_a_fail(self):
        self.fails('E-ME-39', self.good(via='drag-wrong'), '끌기')

    def test_39_fails_on_each_wrong_report(self):
        for over, word in (({'save_enabled': False}, '저장 버튼'), ({'title': '사진 수정'}, '저장 뒤 화면'), ({'ids_open': ['1', '2', '3']}, '열었을 때'),
                           ({'ids_dragged': ['a', 'b', 'c']}, '끈 뒤'), ({'names_after': ['x', 'y', 'z']}, '15-5')):
            with self.subTest(over):
                self.fails('E-ME-39', self.good(**over), word)

    def test_39_fails_when_the_order_did_not_change_or_a_slot_was_shifted_instead_of_swapped(self):
        def unchanged(job):
            rows = self.photos()
            ids = [r['id'] for r in rows]
            self.app_save([{'keep': i} for i in ids], 0)
            return said(ids_open=ids, ids_dragged=[ids[2], ids[1], ids[0]], via='drag', save_enabled=True, title='프로필 편집',
                        names_before=[name_of(r) for r in rows], names_after=[name_of(r) for r in self.photos()])
        self.fails('E-ME-39', unchanged, '위치')

        def shifted(job):
            rows = self.photos()
            ids = [r['id'] for r in rows]
            self.app_save([{'keep': ids[2]}, {'keep': ids[0]}, {'keep': ids[1]}], 1)
            return said(ids_open=ids, ids_dragged=[ids[2], ids[1], ids[0]], via='drag', save_enabled=True, title='프로필 편집',
                        names_before=[name_of(r) for r in rows], names_after=[name_of(r) for r in self.photos()])
        self.fails('E-ME-39', shifted, '맞바꾸')

    def test_39_keeps_the_substitute_note_in_a_fail_too(self):
        (result, note), _ = self.case('E-ME-39', self.good(via='swap-call', save_enabled=False))
        self.assertEqual(result, 'fail', note)
        self.assertIn('저장 버튼', note)
        self.assertIn('swapPhotos', note)  # 끌기 대신 쓴 대체가 fail 메모에도 남는다

    def test_39_fails_when_15_5_was_not_read_before_the_save(self):
        self.fails('E-ME-39', self.good(names_before=['x', 'y', 'z']), '저장 전')

    def test_39_fails_on_a_position_hole_two_avatar_sources_or_a_file_left_in_the_bucket(self):
        def hole(job):
            answer = self.good()(job)
            self.photos()[-1]['position'] = 5
            return answer

        def two_sources(job):
            answer = self.good()(job)
            for row in self.photos():
                row['is_avatar_source'] = True
            return answer

        def leftover(job):
            answer = self.good()(job)
            self.fake.storage['profile-photos'].add('id-1/leftover.jpg')
            return answer
        for answer, word in ((hole, '위치'), (two_sources, '아바타 원본'), (leftover, '저장소')):
            with self.subTest(word):
                self.fails('E-ME-39', answer, word)

    def test_39_is_blocked_when_the_third_photo_cannot_be_added(self):
        self.swallow('POST', r'/rest/v1/profile_photos')
        self.blocked('E-ME-39', self.good(), '준비')

    def test_39_writes_only_to_the_account_it_made(self):
        self.case('E-ME-39', self.good())
        self.writes_only_mine()


class BoundsTest(PhotoBase):
    """E-ME-41 — 사진은 2~4장만."""

    STEPS = [{'count': 4, 'save_enabled': True}, {'count': 3, 'save_enabled': True}, {'count': 2, 'save_enabled': True},
             {'count': 1, 'save_enabled': False}]

    def good(self, steps=None, **over):
        return as_fn(said(**{'steps': self.STEPS if steps is None else steps, 'plus_at_four': 0, 'max_toast': True, 'tiles_after_max': 4, 'gallery_asked': 0, **over}))

    def test_41_four_adds_nothing_and_shows_the_toast_two_keeps_save_on_and_one_turns_it_off(self):
        note, app = self.passes('E-ME-41', self.good())
        self.assertEqual(app.jobs, [{'token_hash': 'h'}])
        self.assertEqual(len(self.photos()), 4)
        self.assertEqual(self.fake.vision_calls, 0)

    def test_41_the_server_refuses_one_and_five_slots_with_422_and_never_calls_vision(self):
        self.passes('E-ME-41', self.good())
        puts = self.fake.by('PUT', '/me/photos')
        self.assertEqual([len(json.loads(p['body']['layout'])) for p in puts], [1, 5])
        for put in puts:  # 모양은 맞고 개수만 틀리다 — 모양 때문에 422 가 나면 이 가설이 보려는 것이 아니다
            self.assertTrue(all(set(slot) == {'keep'} and isinstance(slot['keep'], str) for slot in json.loads(put['body']['layout'])))
        self.assertEqual([p['body']['files'] for p in puts], [0, 0])  # 새 파일이 없다 — Vision 이 불릴 수 없다
        self.assertEqual(self.fake.vision_calls, 0)
        self.assertTrue(all(o == {'retry': False} for m, u, o in self.options if m == 'PUT'))  # 두 번 적용돼도 되지만 한 번만 보낸다
        self.assertEqual(len([1 for m, u, o in self.options if m == 'PUT']), 2)

    def test_41_fails_on_each_wrong_step_toast_or_count(self):
        first, second, third, last = self.STEPS
        for steps, word in (([dict(first, save_enabled=False), second, third, last], '저장 버튼'), ([first, second, dict(third, save_enabled=False), last], '저장 버튼'),
                            ([first, second, third, dict(last, save_enabled=True)], '저장 버튼'), ([dict(first, count=5), second, third, last], '칸 수'),
                            ([first, third, last], '칸 수'), ([], '칸 수')):
            with self.subTest((len(steps), word)):
                self.fails('E-ME-41', self.good(steps=steps), word)
        for over, word in (({'max_toast': False}, '최대 4장'), ({'tiles_after_max': 5}, '칸'), ({'plus_at_four': 1}, '추가 칸'), ({'gallery_asked': 1}, '갤러리')):
            with self.subTest(over):
                self.fails('E-ME-41', self.good(**over), word)

    def test_41_fails_when_the_server_accepts_one_or_five_slots_and_the_photos_change(self):
        self.fake.checks_layout = False
        self.fails('E-ME-41', self.good(), '422')

    def test_41_fails_when_the_422_carries_another_text(self):
        # 422 이긴 한데 "입력한 값을 다시 확인해 주세요" 가 아니면 다른 이유로 막힌 것이다
        self.fake.layout_detail = '다른 문구'
        self.fails('E-ME-41', self.good(), '문구')

    def test_41_fails_when_the_app_saved_something(self):
        def saves(job):
            self.app_save(keep(*reversed(self.photos())), 0)
            return self.good()(job)
        self.fails('E-ME-41', saves, '그대로')

    def test_41_is_blocked_when_the_four_photos_cannot_be_made(self):
        self.swallow('POST', r'/rest/v1/profile_photos')
        self.blocked('E-ME-41', self.good(), '준비')

    def test_41_writes_only_to_the_account_it_made(self):
        self.case('E-ME-41', self.good())
        self.writes_only_mine()


class FaceTest(PhotoBase):
    """E-ME-42 — 얼굴이 없는 사진은 칸에 안 들어간다."""

    def good(self, alone=None, mixed=None):
        return as_fn(said(alone={'before': 2, 'after': 2, 'message': NONE_KEPT, 'toast': True, **(alone or {})},
                          mixed={'before': 2, 'after': 3, 'message': ONE_DROPPED, 'toast': True, **(mixed or {})}))

    def test_42_a_scenery_alone_adds_nothing_and_a_face_with_a_scenery_adds_one(self):
        note, app = self.passes('E-ME-42', self.good())
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'alone': 'scenery.jpg', 'mixed': ['face1.jpg', 'scenery.jpg']}])
        self.assertEqual(len(self.photos()), 2)
        self.assertEqual(self.fake.vision_calls, 0)  # 저장을 누르지 않는다 — 얼굴 판정은 기기 안이고 서버 요청은 없다
        self.assertEqual(self.fake.by('PUT', '/me/photos'), [])

    def test_42_both_files_are_pushed_to_the_phone_once(self):
        self.passes('E-ME-42', self.good())
        pushed = sorted(c[3].rsplit('/', 1)[-1] for c in self.adb_calls if 'push' in c)  # push <PC 파일> <폰 쪽 경로>
        self.assertEqual(pushed, ['face1.jpg', 'scenery.jpg'])

    def test_42_fails_on_each_wrong_round(self):
        for kind, over, word in (('alone', {'after': 3}, '혼자'), ('alone', {'message': ONE_DROPPED}, '혼자'), ('alone', {'toast': False}, '혼자'),
                                 ('alone', {'message': None}, '혼자'), ('mixed', {'after': 2}, '섞'), ('mixed', {'after': 4}, '섞'),
                                 ('mixed', {'message': NONE_KEPT}, '섞'), ('mixed', {'toast': False}, '섞'), ('mixed', {'before': 3}, '섞')):
            with self.subTest((kind, over)):
                self.fails('E-ME-42', self.good(**{kind: over}), word)

    def test_42_pins_the_account_to_exactly_two_photos_before_the_app_starts(self):
        with mock.patch.object(area5_photo, '_ready_photos', wraps=area5_photo._ready_photos) as pin:
            self.passes('E-ME-42', self.good())
        self.assertEqual([call.args[2] for call in pin.call_args_list], [2])

    def test_42_fails_when_the_app_says_no_round(self):
        self.fails('E-ME-42', lambda job: said(), '혼자', '섞')

    def test_42_fails_when_the_app_saved_something(self):
        def saves(job):
            self.app_save(keep(*reversed(self.photos())), 0)
            return self.good()(job)
        self.fails('E-ME-42', saves, '그대로')

    def test_42_is_blocked_before_any_account_when_the_photo_set_lacks_a_file(self):
        (self.folder / 'scenery.jpg').unlink()
        self.blocked('E-ME-42', self.good(), '사진 세트 없음', 'scenery.jpg')
        self.assertEqual(self.fake.users, [])

    def test_42_writes_only_to_the_account_it_made(self):
        self.case('E-ME-42', self.good())
        self.writes_only_mine()


class OpenedApp(MidwayApp):
    """앱이 15-7 을 연 순간의 칸 순서와 마지막 칸의 행을 기억해 둔다 — PC 가 한 장을 지우기 전의 모습이다."""

    def __init__(self, answer, step, events, test):
        super().__init__(answer, step, events)
        self.test = test

    def __call__(self, midway=None, **job):
        self.test.order = [r['id'] for r in self.test.photos()]
        self.test.gone = dict(self.test.photos()[3])
        return super().__call__(midway, **job)


class ConflictTest(PhotoBase):
    """E-ME-44 — 열어 둔 사이 다른 기기에서 사진이 바뀌면 저장이 409."""

    def good(self, **over):
        def answer(job):
            remaining = self.photos()  # PC 가 한 장을 지운 뒤의 서버 사진
            ghost = self.gone['id']
            swapped = [self.order[1], self.order[0], self.order[2], ghost]
            self.reply_seen = self.app_save([{'keep': i} for i in swapped], 0, expect=409)
            return said(**{'ids_open': self.order, 'ids_swapped': swapped, 'via': 'drag', 'error': True, 'error_text': CHANGED,
                           'title_after_error': '사진 수정', 'reopened_tiles': len(remaining), 'reopened_ids': [r['id'] for r in remaining], **over})
        return answer

    def run44(self, answer=None):
        return self.case('E-ME-44', None, OpenedApp(as_fn(answer or self.good()), 'opened', self.events, self))

    def test_44_a_photo_deleted_while_15_7_is_open_makes_the_save_409_and_reopening_shows_the_server_photos(self):
        (result, note), app = self.run44()
        self.assertEqual(result, 'pass', note)
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'swap': [0, 1], 'left': 3}])
        self.assertEqual(self.events, ['step', 'go'])
        self.assertEqual(self.reply_seen[1], {'detail': CHANGED})
        rows = self.photos()
        self.assertEqual([r['id'] for r in rows], self.order[:3])
        self.assertEqual([r['position'] for r in rows], [0, 1, 2])
        self.assertEqual(self.fake.vision_calls, 0)  # 409 는 Vision 앞에서 끝난다

    def test_44_only_the_one_photo_row_is_deleted_by_the_pc_and_with_the_account_filter(self):
        self.run44()
        deletes = self.fake.by('DELETE', '/rest/v1/profile_photos')
        self.assertEqual(len(deletes), 1)
        self.assertEqual(deletes[0]['query']['id'], f"eq.{self.gone['id']}")
        self.assertEqual(deletes[0]['query']['profile_id'], 'eq.id-1')

    def test_44_fails_on_each_wrong_report(self):
        for over, word in (({'error': False}, '오류'), ({'error_text': '다른 문구'}, '오류'), ({'title_after_error': '프로필 편집'}, '머물'),
                           ({'reopened_tiles': 4}, '다시 열'), ({'reopened_ids': ['x', 'y', 'z']}, '다시 열'), ({'via': 'drag-wrong'}, '끌기'),
                           ({'ids_open': ['a', 'b', 'c', 'd']}, '열었을 때'), ({'ids_swapped': ['a', 'b', 'c', 'd']}, '바꾼 뒤')):
            with self.subTest(over):
                (result, note), _ = self.run44(self.good(**over))
                self.assertEqual(result, 'fail', note)
                self.assertIn(word, note)

    def test_44_a_swap_that_worked_through_the_substitute_is_named_in_the_note(self):
        (result, note), _ = self.run44(self.good(via='swap-call'))
        self.assertEqual(result, 'pass', note)
        self.assertIn('swapPhotos', note)

    def test_44_fails_when_the_server_accepts_the_save_and_the_db_changes(self):
        self.fake.checks_owner = False

        def accepts(job):
            swapped = [self.order[1], self.order[0], self.order[2], self.gone['id']]
            self.app_save([{'keep': i} for i in swapped], 0, expect=200)
            return said(ids_open=self.order, ids_swapped=swapped, via='drag', error=True, error_text=CHANGED, title_after_error='사진 수정',
                        reopened_tiles=3, reopened_ids=self.order[:3])
        (result, note), _ = self.run44(accepts)
        self.assertEqual(result, 'fail', note)
        self.assertIn('DB', note)

    def test_44_is_blocked_when_the_photo_row_cannot_be_deleted(self):
        self.swallow('DELETE', r'/rest/v1/profile_photos')
        (result, note), _ = self.run44()
        self.assertEqual(result, 'blocked', note)
        self.assertIn('준비', note)

    def test_44_keeps_the_substitute_note_in_a_fail_too(self):
        (result, note), _ = self.run44(self.good(via='swap-call', error=False))
        self.assertEqual(result, 'fail', note)
        self.assertIn('오류', note)
        self.assertIn('swapPhotos', note)

    def test_44_is_blocked_with_the_reason_when_the_delete_is_refused(self):
        self.fake.handlers.insert(0, ('DELETE', re.compile(r'/rest/v1/profile_photos'), Reply(500, {'message': 'down'})))
        (result, note), _ = self.run44()
        self.assertEqual(result, 'blocked', note)
        self.assertIn('사진 행 지우기 500', note)

    def test_44_writes_only_to_the_account_it_made(self):
        self.run44()
        self.writes_only_mine()


class EdgeOfflineTest(PhotoBase):
    """E-EDGE-03 — 오프라인 저장 실패 뒤 선택한 칸을 유지하고 복구 뒤 한 번만 저장."""

    def app_for(self, answer, between=lambda: None):
        sent = []

        def app(midway=None, **job):
            sent.append(job)
            if midway:
                midway({'step': 'cut'})
                self.offline_state = (len(self.photos()), self.files(), len(self.fake.by('PUT', '/me/photos')))
            return answer(job)

        app.serial, app.hub = 'S', mock.Mock(wait=mock.Mock(side_effect=lambda timeout: (between(), {'step': 'restore'})[1]))
        return app, sent

    def attempt(self, answer, between=lambda: None):
        """[between] 은 첫 멈춤(끊김)과 두 번째 멈춤(복구) 사이 — 앱이 끊긴 채 저장을 누르는 때 서버에 생기는 일."""
        app, sent = self.app_for(answer, between)
        with mock.patch.object(area4.notify, 'airplane') as plane, mock.patch.object(area4.notify, 'ensure_online') as online:
            (result, note), _ = self.case('E-EDGE-03', None, app)
        return (result, note), sent, plane, online

    def good(self, **over):
        def answer(job):
            rows = self.photos()
            self.app_save(keep(*rows) + [{'new': 0}], files=1)
            return said(**{'off_error': NETWORK, 'off_title': TITLES['15-7'], 'off_tiles': 3,
                           'title': TITLES['15-5'], 'names_after': [name_of(r) for r in self.photos()], **over})
        return answer

    def test_03_offline_failure_preserves_selection_and_restored_save_adds_one_photo(self):
        (result, note), sent, plane, online = self.attempt(self.good())
        self.assertEqual(result, 'pass', note)
        self.assertEqual([c.args for c in plane.call_args_list], [('S', True), ('S', False)])
        online.assert_called_once_with('S')
        self.assertEqual(sent, [{'token_hash': 'h', 'photo': 'face1.jpg'}])
        self.assertEqual(self.offline_state[0], 2)
        self.assertEqual(self.offline_state[2], 0)
        self.assertEqual(len(self.photos()), 3)
        self.assertEqual(len(self.files()), 3)
        self.assertEqual(len(self.fake.by('PUT', '/me/photos')), 1)
        self.assertEqual(self.fake.vision_calls, 1)

    def test_03_rejects_missing_network_error_lost_tiles_or_wrong_screen(self):
        for over, word in (({'off_error': None}, '네트워크'), ({'off_title': TITLES['15-5']}, '15-7'),
                           ({'off_tiles': 2}, '칸'), ({'title': TITLES['15-7']}, '15-5')):
            with self.subTest(over):
                (result, note), _, _, online = self.attempt(self.good(**over))
                self.assertEqual(result, 'fail', note)
                self.assertIn(word, note)
                online.assert_called_once_with('S')

    def test_03_fails_when_the_offline_save_reached_the_server(self):
        # 끊긴 채 저장을 누른 사이(첫 멈춤 뒤 · 복구 앞) 서버에 사진이 들어가 버린 경우 — 검사가 첫 멈춤 때만 돌면 못 잡는다
        (result, note), _, _, online = self.attempt(
            self.good(), between=lambda: self.app_save(keep(*self.photos()) + [{'new': 0}], files=1))
        self.assertEqual(result, 'fail', note)
        self.assertIn('끊긴 저장', note)
        online.assert_called_once_with('S')

    def test_03_waits_for_the_network_to_really_drop_before_the_app_saves(self):
        # 비행기 모드를 켠 직후 앱이 저장을 누르면 멀티파트 PUT 이 살아 있는 망으로 나간다 — 켠 다음에 CUT_SETTLE 만큼 쉰다(E-EDGE-01 · 02 와 같은 이유)
        order = mock.Mock()
        app, _ = self.app_for(self.good())
        with mock.patch('time.sleep', order.sleep), mock.patch.object(area4.notify, 'airplane', order.airplane),                 mock.patch.object(area4.notify, 'ensure_online'):
            self.case('E-EDGE-03', None, app)
        calls = [(c[0], c[1][:2]) for c in order.mock_calls if c[0] in ('airplane', 'sleep')]
        first_cut = calls.index(('airplane', ('S', True)))
        self.assertEqual(calls[first_cut + 1], ('sleep', (area5_act.CUT_SETTLE,)))

    def test_03_rejects_false_success_without_server_save(self):
        def no_save(job):
            return said(off_error=NETWORK, off_title=TITLES['15-7'], off_tiles=3,
                        title=TITLES['15-5'], names_after=[name_of(r) for r in self.photos()])
        (result, note), _, _, online = self.attempt(no_save)
        self.assertEqual(result, 'fail', note)
        self.assertIn('DB', note)
        online.assert_called_once_with('S')


# ── E-ME-40 아바타 원본 사진을 뺌 ──────────────────────────────────────────────────────────────────

class RemoveSourceTest(PhotoBase):
    """15-7 에서 아바타 원본(첫 칸)을 빼고 저장하면 새 첫 칸이 원본이 되고 지금 아바타는 그대로이며, 다음 다시 만들기가 새 원본으로 돈다(유료 AI)."""

    worker = WorkerRegenTest.worker

    def good_report(self, **over):
        return said(**{'ids_open': self.ids, 'ids_removed': self.ids[1:], 'title': '프로필 편집', 'avatar_before': 'a.png', 'avatar_after': 'a.png',
                       'generating_seen': True, 'avatar_changed': True, 'generating_gone': True, 'regen_state': 'ready', 'waited_ms': 20000, **over})

    def good(self, source=0, **over):
        def answer(job):
            rows = self.photos()
            self.assertEqual(len(rows), 3)
            self.ids = [r['id'] for r in rows]
            self.app_save(keep(rows[1], rows[2]), source)  # 15-7 에서 원본(첫 칸)을 빼고 저장
            self.app_replace_source()  # 이어서 다시 만들기: 사진 고르기에서 고른 사진이 새 원본 칸을 대신한다(Vision 1번)
            self.assertEqual(self.call_regenerate()[0], 202)
            self.worker()
            return self.good_report(**over)
        return answer

    def test_40_the_new_first_photo_becomes_the_source_the_avatar_stays_and_the_next_regenerate_makes_a_new_one(self):
        (result, note), app = self.case('E-ME-40', self.good())
        self.assertEqual(result, 'pass', note)
        self.assertEqual(app.jobs, [{'token_hash': 'h'}])
        rows = self.photos()
        self.assertEqual(rows[1]['id'], self.ids[2])  # 옛 셋째는 그대로
        self.assertNotIn(rows[0]['id'], self.ids)  # 새로 고른 사진이 원본 칸을 대신해 새 id — 옛 첫째 · 둘째 id 는 없다
        self.assertEqual([r['position'] for r in rows], [0, 1])
        self.assertEqual([r['is_avatar_source'] for r in rows], [True, False])
        self.assertEqual(sorted(a['status'] for a in self.avatars()), ['ready', 'ready'])
        self.assertEqual(self.fake.vision_calls, 1)  # 15-7 저장은 새 파일이 없고(0), 다시 만들기의 사진 교체가 1번
        self.assertEqual(self.pushed_regen_photo(), ['face1.jpg'])  # 사진을 계정을 만들기 전에 앱 캐시로 옮겼다

    def test_40_fails_when_the_new_source_photo_was_never_replaced(self):
        def skipped(job):
            rows = self.photos()
            self.ids = [r['id'] for r in rows]
            self.app_save(keep(rows[1], rows[2]), 0)
            self.assertEqual(self.call_regenerate()[0], 202)  # 사진 교체 없이 등록만 — 옛 흐름
            self.worker()
            return self.good_report()
        (result, note), _ = self.case('E-ME-40', skipped)
        self.assertEqual(result, 'fail', note)
        self.assertIn('원본', note)

    def test_40_is_behind_the_real_ai_gate_and_makes_no_request_without_it(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            (result, note), app = self.case('E-ME-40', said())
        self.assertEqual(result, 'blocked')
        self.assertIn('E2E_REAL_AI', note)
        self.assertEqual(self.fake.sent, [])
        self.assertEqual(app.jobs, [])

    def test_40_the_time_limit_covers_the_worker_wait(self):
        self.assertGreaterEqual(tools.CASE_LIMITS['E-ME-40'], 900)

    def test_40_fails_when_the_source_flag_is_not_on_the_new_first_photo(self):
        (result, note), _ = self.case('E-ME-40', self.good(source=1))
        self.assertEqual(result, 'fail', note)
        self.assertIn('원본', note)

    def test_40_fails_on_each_wrong_app_report(self):
        for over, word in (({'ids_open': ['x', 'y', 'z']}, '열었을 때'), ({'ids_removed': ['x', 'y']}, '뺀'), ({'title': '사진 수정'}, '저장 뒤 화면'),
                           ({'avatar_after': 'b.png'}, '아바타'), ({'avatar_changed': False}, '그림'), ({'regen_state': 'failed'}, '상태')):
            with self.subTest(over):
                self.reset_paid()
                (result, note), _ = self.case('E-ME-40', self.good(**over))
                self.assertEqual(result, 'fail', note)
                self.assertIn(word, note)

    def test_40_fails_when_a_ready_avatar_was_changed_by_the_photo_save(self):
        def eats(job):
            answer = self.good()(job)
            self.avatars(status='ready')[0]['storage_path'] = 'id-1/other.png'
            return answer
        (result, note), _ = self.case('E-ME-40', eats)
        self.assertEqual(result, 'fail', note)
        self.assertIn('아바타 행', note)

    def test_40_fails_when_the_worker_never_made_a_new_avatar(self):
        def stuck(job):
            rows = self.photos()
            self.app_save(keep(rows[1], rows[2]), 0)
            self.app_replace_source()
            return said(ids_open=[r['id'] for r in rows], ids_removed=[r['id'] for r in rows[1:]], title='프로필 편집', avatar_before='a.png',
                        avatar_after='a.png', generating_seen=True, avatar_changed=True, generating_gone=True, regen_state='ready', waited_ms=1)
        (result, note), _ = self.case('E-ME-40', stuck)
        self.assertEqual(result, 'fail', note)
        self.assertIn('완성', note)

    def test_40_writes_only_to_the_account_it_made(self):
        self.case('E-ME-40', self.good())
        self.writes_only_mine()


# ── E-ME-43 부적절한 사진을 섞어 저장 ───────────────────────────────────────────────────────────────

class UnsafeMixedTest(PhotoBase):
    """얼굴 사진 + 부적절 사진을 함께 저장하면 서버가 422 로 막고, 둘 다 안 올라가며 DB · 저장소가 그대로다."""

    def good(self, **over):
        def answer(job):
            self.fake.unsafe = True
            self.reply_seen = self.app_save(keep(*self.photos()) + [{'new': 0}, {'new': 1}], 0, files=2, expect=422)
            return said(**{'tiles_before': 2, 'tiles_after': 4, 'error': True, 'error_text': NOT_SAFE, 'title_after_error': '사진 수정', **over})
        return answer

    def test_43_the_unsafe_photo_makes_the_whole_save_fail_with_the_message_and_nothing_changes(self):
        note, app = self.passes('E-ME-43', self.good())
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'photo': 'face1.jpg', 'unsafe': 'unsafe.jpg'}])
        self.assertEqual(self.reply_seen[1], {'detail': NOT_SAFE})
        self.assertEqual(len(self.photos()), 2)
        self.assertEqual(self.files(), sorted(r['storage_path'] for r in self.photos()))
        self.assertEqual(self.avatars(status='ready')[0]['status'], 'ready')

    def test_43_both_photos_are_pushed_to_the_phone_once_before_the_app_starts(self):
        self.passes('E-ME-43', self.good())
        pushed = [c for c in self.adb_calls if 'push' in c]
        self.assertEqual(sorted(Path(c[2]).name for c in pushed), ['face1.jpg', 'unsafe.jpg'])

    def test_43_is_not_behind_the_real_ai_gate(self):
        self.assertNotEqual(area5_photo.PHONE['E-ME-43'].__name__, 'case')

    def test_43_is_blocked_before_any_account_when_the_photo_set_lacks_the_unsafe_file(self):
        (self.folder / 'unsafe.jpg').unlink()
        self.blocked('E-ME-43', self.good(), '사진 세트 없음', 'unsafe.jpg')
        self.assertEqual(self.fake.users, [])

    def test_43_fails_on_each_wrong_app_report(self):
        for over, word in (({'error': False}, '오류'), ({'error_text': '다른 문구'}, '오류'), ({'title_after_error': '프로필 편집'}, '머물'),
                           ({'tiles_after': 3}, '칸'), ({'tiles_before': 3}, '칸')):
            with self.subTest(over):
                self.fails('E-ME-43', self.good(**over), word)

    def test_43_fails_when_the_server_let_the_unsafe_photo_in(self):
        def accepts(job):
            self.app_save(keep(*self.photos()) + [{'new': 0}, {'new': 1}], 0, files=2, expect=200)
            return said(tiles_before=2, tiles_after=4, error=True, error_text=NOT_SAFE, title_after_error='사진 수정')
        self.fails('E-ME-43', accepts, 'DB')

    def test_43_writes_only_to_the_account_it_made(self):
        self.case('E-ME-43', self.good())
        self.writes_only_mine()


# ── 쓰기 가드 ───────────────────────────────────────────────────────────────────────────────────────

class GuardTest(PhotoBase):
    """이번 실행이 만든 계정이 아니면 어떤 쓰기도 서버에 닿기 전에 멈춘다 — `_home` 을 거치지 않고 낯선 id 로 직접 부른다."""

    def stranger(self):
        patcher = mock.patch.object(area2, '_guard', REAL_GUARD)
        patcher.start()
        self.addCleanup(patcher.stop)
        return {'id': 'stranger-1', 'token': 'tok-9'}

    def refuses(self, call):
        stranger = self.stranger()
        with self.assertRaises(tools.Blocked) as caught:
            call(stranger)
        self.assertIn('stranger-1', str(caught.exception))
        self.assertEqual(self.fake.sent, [])

    def test_the_hearts_writer_refuses_a_stranger(self):
        self.refuses(lambda who: area5_photo._hearts_to(self.run_, who, 5))

    def test_the_photo_adder_refuses_a_stranger_before_uploading_a_file(self):
        self.refuses(lambda who: area5_photo._ready_photos(self.run_, who, 4))

    def test_the_photo_deleter_refuses_a_stranger(self):
        self.refuses(lambda who: area5_photo._drop_photo(self.run_, who, {'id': 'p1'}))

    def test_the_avatar_watcher_refuses_a_stranger_before_it_starts(self):
        self.refuses(lambda who: area5_photo._Watcher(self.run_, who, set()))

    def test_the_guard_lets_an_account_this_run_made_through(self):
        self.run_.out.mkdir(parents=True, exist_ok=True)
        (self.run_.out / 'accounts.json').write_text(json.dumps([{'id': 'id-1'}]), encoding='utf-8')
        patcher = mock.patch.object(area2, '_guard', REAL_GUARD)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.fake.rows('entitlements').append({'profile_id': 'id-1', 'heart_balance': 0})
        area5_photo._hearts_to(self.run_, {'id': 'id-1', 'token': 'tok-1'}, 5)
        self.assertEqual(self.fake.balance(), 5)

    def test_the_guard_is_called_before_the_module_writes_in_a_real_case(self):
        guarded = []
        with mock.patch.object(area2, '_guard', lambda run, *ids: guarded.extend(ids)):
            self.case('E-ME-41', as_fn(said()))
        self.assertIn('id-1', guarded)


# ── 앱의 말 ─────────────────────────────────────────────────────────────────────────────────────────

class AppAnswerTest(PhotoBase):
    """한 번 켜서 한 번 말하는 여섯 · 한 번 멈추는 둘 — 앱의 blocked 는 blocked, 말이 없으면 fail."""

    def app(self, name, answer):
        if name in ('E-ME-13', 'E-ME-44'):
            return MidwayApp(as_fn(answer), 'opened', self.events)
        if name == 'E-ME-14':
            return MidwayApp(as_fn(answer), 'ready', self.events)
        return App(as_fn(answer))

    def test_a_blocked_app_is_blocked_and_a_silent_or_failed_app_is_a_fail(self):
        for case in BUNDLE:
            with self.subTest(case):
                self.reset_paid()
                self.blocked(case, None, '못 찾음', app=self.app(case, {'result': 'blocked', 'note': '못 찾음'}))
                self.reset_paid()
                self.fails(case, None, '답하지 않음', app=self.app(case, lambda job: None))
                self.reset_paid()
                self.fails(case, None, '앱이 본 것과 다름', app=self.app(case, {'result': 'fail', 'note': '앱이 본 것과 다름'}))


if __name__ == '__main__':
    unittest.main()
