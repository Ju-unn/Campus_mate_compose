"""영역 5 API 가설 4개(E-ME-17 · E-ME-37 · E-ME-45 · E-EDGE-22) 시험 — 운영 없이 가짜 서버로 돈다. 저장소 루트에서 `python -m unittest e2e.test_area5_api`.

가짜 서버([ApiFake])는 영역 3 시험의 표 저장소에 다시 만들기 · 프로필 저장 · 사진 저장 · 하트 장부를 서버 규칙 그대로 얹었다.
올바른 서버면 pass, 규칙 하나를 어긴 서버([ApiFake.rules] 를 한 군데 바꿈)면 fail 이어야 한다. 가짜 서버는 유료 AI 를 부르지 않는다(호출 0).
"""

import itertools
import json
import os
import re
import threading
import unittest
import uuid
from contextlib import contextmanager
from email.parser import BytesParser
from email.policy import default
from unittest import mock
from urllib.parse import urlsplit

from e2e import area2_phone3, area5_api, tools
from e2e.test_area3 import Base, Fake, mismatched_keys
from e2e.tools import Reply

NOT_CREATED = '아바타를 먼저 만들어 주세요'
SOURCE_REQUIRED = '아바타 원본 사진을 먼저 골라 주세요'
INVALID = '입력한 값을 다시 확인해 주세요'
UNREADABLE = '사진을 다시 확인해 주세요'
PHOTOS_CHANGED = '사진이 바뀌었어요, 다시 열어 주세요'
LOW_HEARTS = '하트가 모자라요'
NULL_REASON = 'Value error, 빈 값으로는 바꿀 수 없어요'
EMPTY_REASON = 'Value error, 고칠 칸이 없어요'
PNG = b'\x89PNG\r\n\x1a\n'
JPEG = b'\xff\xd8\xff'
CASE_NAMES = ['E-ME-17', 'E-ME-37', 'E-ME-45', 'E-EDGE-22']


def _who(sent):
    return f"id-{sent['auth'].removeprefix('tok-')}"


def parse_form(raw):
    """multipart 본문 → (칸들, 파일 바이트들)."""
    data, kind = raw
    message = BytesParser(policy=default).parsebytes(f'Content-Type: {kind}\r\n\r\n'.encode() + data)
    fields, files = {}, []
    for part in message.iter_parts():
        if part.get_filename() is not None:
            files.append(part.get_payload(decode=True))
        else:
            fields[part.get_param('name', header='content-disposition')] = part.get_content()
    return fields, files


class ApiFake(Fake):
    """영역 3 의 가짜 서버 + 다시 만들기 · 프로필 저장 · 사진 저장 · 하트 장부. 번호(id-N)와 토큰(tok-N)은 만든 순서가 같다.
    다시 만들기는 [ready_after] 번 읽히고 나면 완성(ready)으로 바뀌며 그때 하트를 뺀다 — 워커가 완성을 적은 뒤에 뺀다(T2)."""

    def __init__(self):
        super().__init__()
        self.lock = threading.Lock()
        self.profiles = {}
        self.files = set()  # (버킷, 경로)
        self.ticks = {}
        self.forms = []  # PUT /me/photos 로 받은 (칸들, 파일들)
        self.options = []  # (메서드, 경로, call 에 준 옵션)
        self.enqueued = 0  # 워커에 넘긴 작업 수 = 유료 AI 호출 수
        self._raw = None
        self.seen = []  # 다시 만들기 요청이 닿았을 때의 (ready 장 수, 원본 사진 표시 여부)
        self.marked = []  # 다시 만들기 요청이 닿았을 때 유료 표시(_PAID)가 이미 있었나
        self.rules = {'check_ready': True, 'check_source': True, 'one_pending': True, 'ready_after': 2, 'charges': 1,
                      'charge_at_post': False, 'fail_generation': False, 'pending_on_409': False,
                      'second_409': False, 'pending_word': 'pending', 'wrong_ref': False,
                      'null_ok': False, 'empty_ok': False, 'write_then_reject': False,
                      'photos_clear_first': False, 'photos_upload_first': False, 'text_ok': False}
        for method, pattern, handler in (
                ('POST', r'/profile-onboarding/basic-info', self._basic), ('POST', r'/profile-onboarding/bio', self._bio),
                ('POST', r'/profile-onboarding/photos', self._onboarding_photo), ('POST', r'/me/avatar/regenerate', self._regenerate),
                ('PUT', r'/me/photos', self._put_photos), ('PATCH', r'/me/profile', self._patch_profile),
                ('POST', r'/rest/v1/rpc/grant_hearts', self._grant), ('POST', r'/storage/v1/object/list/[^/]+', self._list)):
            self.on(method, pattern, handler)

    def __call__(self, method, url, headers=None, body=None, raw=None, **options):
        self._raw = raw
        self.options.append((method, urlsplit(url).path, options))
        return super().__call__(method, url, headers, body, raw, **options)

    # ── 표 ──
    def rows(self, table):
        return self.tables.setdefault(table, [])

    def profile(self, pid):
        return self.profiles.setdefault(pid, {'id': pid, 'nickname': None, 'height_cm': None, 'bio': None, 'status': 'pending'})

    def _table(self, method, name, sent):
        query, body = sent['query'], sent['body']
        if name == 'profiles' and 'id' in query:
            row = self.profile(query['id'][3:])
            if method == 'PATCH':
                row.update(body)
                return Reply(200, None)
            return Reply(200, [dict(row)])
        if method == 'POST':
            if mismatched_keys(body):
                return mismatched_keys(body)
            for row in body if isinstance(body, list) else [body]:
                row.setdefault('id', str(uuid.uuid4()))
        if name == 'profile_avatars' and method == 'GET':
            self._work()
        return super()._table(method, name, sent)

    def wallet(self, pid):
        row = next((r for r in self.rows('entitlements') if r['profile_id'] == pid), None)
        if row is None:
            row = {'profile_id': pid, 'heart_balance': 0}
            self.rows('entitlements').append(row)
        return row

    def _move(self, pid, amount, reason, ref=None):
        self.wallet(pid)['heart_balance'] += amount
        self.rows('heart_transactions').append({'profile_id': pid, 'reason': reason, 'amount': amount, 'ref_id': ref})

    def _work(self):
        """읽을 때마다 워커가 한 걸음 — 다 걸으면 완성(또는 실패)을 적고 하트를 뺀다."""
        for row in self.rows('profile_avatars'):
            if row['status'] != 'pending':
                continue
            self.ticks[row['id']] = self.ticks.get(row['id'], 0) + 1
            if self.ticks[row['id']] > self.rules['ready_after']:
                if self.rules['fail_generation']:
                    row['status'] = 'failed'
                    continue
                row['status'], row['storage_path'] = 'ready', f"{row['profile_id']}/made.png"
                for _ in range(self.rules['charges']):
                    self._move(row['profile_id'], -10, 'avatar_regen', 'other-attempt' if self.rules['wrong_ref'] else row['id'])

    # ── 온보딩 · 하트 · 저장소 ──
    def _basic(self, sent):
        self.profile(_who(sent)).update(nickname=sent['body']['nickname'], height_cm=sent['body']['height_cm'])
        return Reply(200, {})

    def _bio(self, sent):
        self.profile(_who(sent)).update(bio=sent['body']['bio'], status='active')
        return Reply(200, {})

    def _onboarding_photo(self, sent):
        me, (fields, _) = _who(sent), parse_form(self._raw)
        path = f'{me}/{uuid.uuid4().hex}.png'
        self.files.add(('profile-photos', path))
        self.rows('profile_photos').append({'id': str(uuid.uuid4()), 'profile_id': me, 'storage_path': path,
                                            'position': int(fields['position']), 'is_avatar_source': fields['is_avatar_source'] == 'true'})
        return Reply(200, {'ok': True})

    def _grant(self, sent):
        body = sent['body']
        self._move(body['p_profile_id'], body['p_amount'], body['p_reason'], body['p_ref_id'])
        return Reply(200, None)

    def _list(self, sent):
        bucket, prefix = sent['path'].rsplit('/', 1)[1], sent['body']['prefix'] + '/'
        return Reply(200, [{'name': path[len(prefix):], 'id': 'f'} for b, path in sorted(self.files) if b == bucket and path.startswith(prefix)])

    # ── 서버 규칙 ──
    def _pending_row(self, me):
        attempt = {'id': str(uuid.uuid4()), 'profile_id': me, 'status': 'pending', 'storage_path': None}
        self.rows('profile_avatars').append(attempt)
        self.enqueued += 1  # 워커 작업 등록 = 유료 AI 호출
        return attempt

    def _regenerate(self, sent):
        me = _who(sent)
        self.marked.append(area5_api.EDGE_22 in area2_phone3._PAID)
        with self.lock:
            mine = [r for r in self.rows('profile_avatars') if r['profile_id'] == me]
            ready = [r for r in mine if r['status'] == 'ready']
            has_source = any(p['profile_id'] == me and p.get('is_avatar_source') for p in self.rows('profile_photos'))
            self.seen.append((len(ready), has_source))
            if not ready and self.rules['check_ready']:
                if self.rules['pending_on_409']:  # 409 를 내고도 만드는 중 행을 남기는 서버
                    self._pending_row(me)
                return Reply(409, {'detail': NOT_CREATED})
            if not has_source and self.rules['check_source']:
                return Reply(409, {'detail': SOURCE_REQUIRED})
            cost = 0 if len(ready) <= 1 else 10
            if cost and self.wallet(me)['heart_balance'] < cost:
                return Reply(402, {'detail': LOW_HEARTS})
            duplicate = self.rules['one_pending'] and any(r['status'] == 'pending' for r in mine)  # 부분 유니크 인덱스(23505)
            if duplicate and self.rules['second_409']:
                return Reply(409, {'detail': '이미 만드는 중이에요'})
            if not duplicate:
                attempt = self._pending_row(me)
                if self.rules['charge_at_post']:
                    self._move(me, -cost, 'avatar_regen', attempt['id'])
            return Reply(202, {'status': self.rules['pending_word'], 'avatar_url': None, 'compensation_hearts': None})

    def _patch_profile(self, sent):
        me, body = _who(sent), sent['body']
        if not body and not self.rules['empty_ok']:
            reason = EMPTY_REASON
        elif any(v is None for v in body.values()) and not self.rules['null_ok']:
            reason = NULL_REASON
        else:
            self.profile(me).update(body)
            return Reply(200, {'ok': True})
        if self.rules['write_then_reject']:
            self.profile(me).update(body)
        return Reply(422, {'detail': [{'type': 'value_error', 'loc': ['body'], 'msg': reason}]})

    def _put_photos(self, sent):
        me = _who(sent)
        fields, files = parse_form(self._raw)
        self.forms.append((fields, files))
        mine = [r for r in self.rows('profile_photos') if r['profile_id'] == me]
        if self.rules['photos_clear_first']:  # 검사하기 전에 지우는 서버
            self.tables['profile_photos'] = [r for r in self.rows('profile_photos') if r['profile_id'] != me]
        try:
            slots, source = json.loads(fields['layout']), int(fields['avatar_source'])
            keep = [s['keep'] for s in slots if list(s) == ['keep']]
            new = [s['new'] for s in slots if list(s) == ['new']]
            valid = 2 <= len(slots) <= 4 and len(keep) + len(new) == len(slots) and len(set(keep)) == len(keep) \
                and sorted(new) == list(range(len(files))) and 0 <= source < len(slots)
        except (KeyError, ValueError, TypeError):
            valid = False
        if not valid:
            return Reply(422, {'detail': INVALID})
        if not set(keep) <= {r['id'] for r in mine}:
            return Reply(409, {'detail': PHOTOS_CHANGED})
        if self.rules['photos_upload_first']:  # 읽을 수 있는지 보기 전에 올리는 서버
            for _ in files:
                self.files.add(('profile-photos', f'{me}/{uuid.uuid4().hex}.png'))
        if not self.rules['text_ok'] and not all(data.startswith((JPEG, PNG)) for data in files):
            return Reply(400, {'detail': UNREADABLE})
        by_id, stored = {r['id']: r for r in mine}, []
        for position, slot in enumerate(slots):
            if 'keep' in slot:
                stored.append({**by_id[slot['keep']], 'position': position})
                continue
            path = f'{me}/{uuid.uuid4().hex}.png'
            self.files.add(('profile-photos', path))
            stored.append({'id': str(uuid.uuid4()), 'profile_id': me, 'storage_path': path, 'position': position, 'is_avatar_source': False})
        self.tables['profile_photos'] = [r for r in self.rows('profile_photos') if r['profile_id'] != me] + stored
        return Reply(200, {'ok': True})


class ApiBase(Base):
    def setUp(self):
        super().setUp()
        self.fake = ApiFake()
        for patcher in (mock.patch.object(tools, 'call', self.fake), mock.patch.object(area2_phone3.time, 'sleep', lambda s: None)):
            patcher.start()
            self.addCleanup(patcher.stop)
        area2_phone3._PAID.clear()
        area5_api._FAILED.clear()
        self.addCleanup(area2_phone3._PAID.clear)
        self.addCleanup(area5_api._FAILED.clear)

    def case(self, name):
        return area5_api.attempt(self.run_, name)

    def passes(self, name):
        result, note = self.case(name)
        self.assertEqual(result, 'pass', note)
        return note

    def fails(self, name, *words):
        result, note = self.case(name)
        self.assertEqual(result, 'fail', note)
        for word in words:
            self.assertIn(word, note)
        return note

    def blocked(self, name, *words):
        result, note = self.case(name)
        self.assertEqual(result, 'blocked', note)
        for word in words:
            self.assertIn(word, note)

    def first(self, method, handler):
        """가장 먼저 맞는 답을 하나 끼운다 — 어긋난 서버."""
        self.fake.handlers.insert(0, (method, re.compile(handler[0]), handler[1]))

    def sent_to(self, method, path):
        return self.fake.by(method, path)

    def regenerate_retries(self):
        return [o.get('retry') for m, p, o in self.fake.options if (m, p) == ('POST', '/me/avatar/regenerate')]


@contextmanager
def clock(step):
    """time.monotonic 이 부를 때마다 [step] 초씩 가는 가짜 시계 — 기다림이 끝나는 길을 진짜로 기다리지 않고 본다."""
    with mock.patch.object(area5_api.time, 'monotonic', side_effect=itertools.count(0, step)):
        yield


@contextmanager
def paid():
    with mock.patch.dict(os.environ, {'E2E_REAL_AI': '1'}):
        yield


class RegistryTest(unittest.TestCase):
    def test_bundle_is_exactly_the_four_hypotheses(self):
        self.assertEqual(area5_api.BUNDLES, {'area5-api': CASE_NAMES})
        self.assertEqual(sorted(area5_api.CASES), sorted(CASE_NAMES))

    def test_the_runner_knows_the_bundle_and_every_case_belongs_to_this_module(self):
        from e2e import __main__ as cli
        self.assertEqual(cli.BUNDLES['area5-api'], CASE_NAMES)
        for case in CASE_NAMES:
            self.assertIs(cli.API_CASES[case], area5_api)


class SafetyNetTest(ApiBase):
    def test_every_case_ends_as_fail_or_blocked_when_the_server_is_down(self):
        down = Fake()
        for method in ('GET', 'POST', 'PUT', 'PATCH', 'DELETE'):
            down.on(method, r'.*', Reply(500, {'detail': '서버'}))
        with mock.patch.object(tools, 'call', down), paid():
            for name in CASE_NAMES:
                result, note = self.case(name)
                self.assertIn(result, ('fail', 'blocked'), name)
                self.assertIsInstance(note, str, name)


class Me17Test(ApiBase):
    def test_no_ready_avatar_and_no_source_photo_are_each_409_with_their_own_sentence_and_nothing_is_queued(self):
        self.passes('E-ME-17')
        calls = self.sent_to('POST', '/me/avatar/regenerate')
        self.assertEqual([c['auth'] for c in calls], ['tok-1', 'tok-1'])
        self.assertEqual(self.fake.enqueued, 0)  # 유료 AI 호출 0
        self.assertEqual([r['status'] for r in self.fake.rows('profile_avatars')], ['ready'])  # 둘째 경우의 준비물뿐, pending 0
        self.assertFalse(any(p['is_avatar_source'] for p in self.fake.rows('profile_photos')))
        # 되돌릴 수 없는 요청이라 끊겨도 다시 보내지 않는다.
        self.assertEqual(self.regenerate_retries(), [False, False])

    def test_the_first_request_goes_out_with_the_source_flag_already_off(self):
        # 비용 안전장치 — ready 검사를 잃은 서버가 202 를 내도 워커가 원본이 없어 AI 를 안 부른다(둘째 경우의 준비는 그대로).
        self.passes('E-ME-17')
        self.assertEqual(self.fake.seen, [(0, False), (1, False)])

    def test_a_server_that_lost_the_ready_check_ends_the_first_case_as_a_wording_fail_and_queues_nothing(self):
        self.fake.rules['check_ready'] = False
        note = self.fails('E-ME-17', 'ready 0장', '문구')
        self.assertNotIn('202', note)
        self.assertEqual(self.fake.enqueued, 0)  # 유료 AI 호출 0

    def test_fails_when_both_checks_are_lost_and_the_202_is_reported(self):
        self.fake.rules['check_ready'] = self.fake.rules['check_source'] = False
        self.fails('E-ME-17', '202', 'pending')

    def test_fails_when_a_409_still_leaves_a_pending_row(self):
        self.fake.rules['pending_on_409'] = True
        self.fails('E-ME-17', 'ready 0장 뒤', 'pending 1개')

    def test_fails_when_only_the_source_sentence_is_wrong(self):
        original, calls = self.fake._regenerate, []

        def second_is_wrong(sent):  # 호출 순번으로 가른다 — 둘째 요청(원본 사진 경우)만 문구가 틀리다
            calls.append(sent)
            reply = original(sent)
            return Reply(409, {'detail': '아무 문구'}) if len(calls) == 2 else reply
        self.first('POST', (r'/me/avatar/regenerate', second_is_wrong))
        note = self.fails('E-ME-17', '원본 사진 표시 없음', '문구')
        self.assertNotIn('ready 0장', note)

    def test_fails_when_a_missing_source_photo_is_let_through(self):
        self.fake.rules['check_source'] = False
        self.fails('E-ME-17', '202', 'pending')

    def test_fails_when_the_sentence_is_not_the_one_for_that_reason(self):
        self.first('POST', (r'/me/avatar/regenerate', Reply(409, {'detail': SOURCE_REQUIRED})))
        self.fails('E-ME-17', 'ready 0장', '문구')

    def test_is_blocked_when_the_account_never_had_a_ready_avatar_so_the_409_would_prove_nothing(self):
        self.first('GET', (r'/rest/v1/profile_avatars', Reply(200, [])))
        self.blocked('E-ME-17', '준비')
        self.assertEqual(self.sent_to('POST', '/me/avatar/regenerate'), [])


class Me37Test(ApiBase):
    def test_null_height_and_empty_body_are_422_for_their_own_reason_and_the_profile_is_untouched(self):
        self.passes('E-ME-37')
        bodies = [s['body'] for s in self.sent_to('PATCH', '/me/profile')]
        self.assertEqual(bodies, [{'height_cm': None}, {}])
        self.assertEqual(self.fake.profile('id-1')['height_cm'], 170)

    def test_fails_when_null_height_is_accepted(self):
        self.fake.rules['null_ok'] = True
        self.fails('E-ME-37', '200', 'height_cm')

    def test_fails_when_an_empty_body_is_accepted(self):
        self.fake.rules['empty_ok'] = True
        self.fails('E-ME-37', '200')

    def test_fails_when_the_request_is_rejected_but_the_profile_was_already_written(self):
        self.fake.rules['write_then_reject'] = True
        self.fails('E-ME-37', 'DB', 'height_cm')

    def test_fails_when_the_422_is_for_another_reason(self):
        self.first('PATCH', (r'/me/profile', Reply(422, {'detail': [{'msg': 'Field required'}]})))
        self.fails('E-ME-37', '문구')

    def test_a_profile_row_that_cannot_be_read_is_blocked_not_equal(self):
        self.first('GET', (r'/rest/v1/profiles', Reply(200, [])))
        self.blocked('E-ME-37', '준비')


class Me45Test(ApiBase):
    def test_one_slot_and_a_repeated_id_are_422_and_a_text_file_is_400_and_nothing_changes(self):
        self.passes('E-ME-45')
        ids = [p['id'] for p in self.fake.rows('profile_photos')]
        layouts = [json.loads(fields['layout']) for fields, _ in self.fake.forms]
        self.assertEqual(layouts, [[{'keep': ids[0]}], [{'keep': ids[0]}, {'keep': ids[0]}], [{'keep': ids[0]}, {'new': 0}]])
        self.assertEqual([len(files) for _, files in self.fake.forms], [0, 0, 1])
        self.assertEqual(self.fake.forms[2][1], [b'hello'])  # 글자 파일
        self.assertEqual([s['method'] for s in self.sent_to('PUT', '/me/photos')], ['PUT'] * 3)
        self.assertEqual(len(ids), 2)
        self.assertEqual(len(self.fake.files), 2)

    def test_fails_when_a_rejected_request_already_cleared_the_rows(self):
        self.fake.rules['photos_clear_first'] = True
        self.fails('E-ME-45', 'profile_photos')

    def test_fails_when_a_file_is_stored_before_it_is_checked(self):
        self.fake.rules['photos_upload_first'] = True
        self.fails('E-ME-45', '버킷')

    def test_fails_when_the_text_file_is_accepted(self):
        self.fake.rules['text_ok'] = True
        self.fails('E-ME-45', '텍스트 파일', '200')

    def test_fails_when_the_422_carries_another_sentence(self):
        self.first('PUT', (r'/me/photos', Reply(422, {'detail': [{'msg': 'Field required'}]})))
        self.fails('E-ME-45', '칸 1개', '문구')

    def test_is_blocked_when_the_account_has_no_stored_photos_so_unchanged_would_prove_nothing(self):
        self.first('POST', (r'/profile-onboarding/photos', Reply(200, {'ok': True})))
        self.blocked('E-ME-45', '준비')
        self.assertEqual(self.sent_to('PUT', '/me/photos'), [])


class Edge22Test(ApiBase):
    def test_with_the_gate_shut_nothing_is_made_and_no_request_is_sent(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            self.blocked('E-EDGE-22', 'E2E_REAL_AI')
        self.assertEqual(self.fake.users, [])
        self.assertEqual(self.sent_to('POST', '/me/avatar/regenerate'), [])

    def test_two_at_once_are_two_202_one_pending_row_and_one_charge_after_it_is_made(self):
        with paid():
            note = self.passes('E-EDGE-22')
        self.assertIn('−10', note)
        calls = self.sent_to('POST', '/me/avatar/regenerate')
        self.assertEqual([c['auth'] for c in calls], ['tok-1', 'tok-1'])
        self.assertEqual(self.fake.enqueued, 1)  # 가짜 서버도 작업은 하나(유료 AI 호출은 가짜 서버에서 0)
        self.assertEqual(sorted(r['status'] for r in self.fake.rows('profile_avatars')), ['ready'] * 3)
        self.assertEqual([r['amount'] for r in self.fake.rows('heart_transactions') if r['reason'] == 'avatar_regen'], [-10])
        self.assertEqual(self.fake.wallet('id-1')['heart_balance'], 27)
        # 동시에 두 번이라 끊겨도 다시 보내지 않는다.
        self.assertEqual(self.regenerate_retries(), [False, False])

    def test_the_paid_marker_is_set_before_the_first_request(self):
        with paid():
            self.passes('E-EDGE-22')
        self.assertEqual(self.fake.marked, [True, True])  # 두 요청이 서버에 닿을 때 이미 유료 표시가 있었다
        self.assertIn('E-EDGE-22', area2_phone3._PAID)

    def test_fails_when_two_pending_rows_are_made_and_does_not_wait_for_them(self):
        self.fake.rules['one_pending'] = False
        with paid(), clock(1):
            self.fails('E-EDGE-22', '새 아바타 행 2개')
        self.assertLessEqual(max(self.fake.ticks.values()), 1)  # 한 번 읽어 보고 기다리지 않고 바로 판정

    def test_fails_when_the_balance_is_charged_twice(self):
        self.fake.rules['charges'] = 2
        with paid():
            self.fails('E-EDGE-22', '잔액', 'avatar_regen')

    def test_fails_when_the_hearts_leave_while_it_is_being_made(self):
        self.fake.rules['charge_at_post'], self.fake.rules['charges'] = True, 0
        with paid():
            self.fails('E-EDGE-22', '만드는 중 잔액')

    def test_fails_when_the_hearts_never_leave(self):
        self.fake.rules['charges'] = 0
        with paid(), clock(30):
            self.fails('E-EDGE-22', '완성 뒤 잔액')

    def test_fails_when_the_second_request_is_409_instead_of_the_same_202(self):
        self.fake.rules['second_409'] = True
        with paid():
            note = self.fails('E-EDGE-22', '409', '기대 202')
        for word in ('새 아바타 행', '잔액', 'ref_id', '원장'):
            self.assertNotIn(word, note)  # 새 행 1개 · 하트 · 원장은 맞다 — 둘째 요청 하나만 어긋남

    def test_fails_when_the_202_body_is_not_pending(self):
        self.fake.rules['pending_word'] = 'queued'
        with paid():
            self.fails('E-EDGE-22', "'queued'", '기대 pending')

    def test_fails_when_the_ledger_points_at_another_attempt(self):
        self.fake.rules['wrong_ref'] = True
        with paid():
            note = self.fails('E-EDGE-22', 'ref_id')
        self.assertNotIn('요청', note)  # 두 요청 · 새 행 · 잔액은 맞다 — 원장 id 하나만 어긋남

    def test_a_failed_generation_is_blocked_not_counted_against_the_server(self):
        self.fake.rules['fail_generation'] = True
        with paid():
            self.blocked('E-EDGE-22', 'AI 쪽')

    def test_waiting_gives_up_after_ten_minutes_as_blocked(self):
        self.fake.rules['ready_after'] = 10 ** 9
        with paid(), clock(60):
            self.blocked('E-EDGE-22', '600초')

    def test_a_second_attempt_never_pays_again_and_keeps_the_first_fail(self):
        self.fake.rules['one_pending'] = False
        with paid():
            first = self.case('E-EDGE-22')
            spent = self.fake.enqueued
            second = self.case('E-EDGE-22')
        self.assertEqual(first[0], 'fail')
        self.assertEqual(second, first)  # run_case 의 재시도가 fail 을 blocked 로 덮지 않는다
        self.assertEqual(self.fake.enqueued, spent)
        self.assertEqual(len(self.sent_to('POST', '/me/avatar/regenerate')), 2)

    def test_a_balance_other_than_37_after_the_gift_is_blocked_before_any_paid_request(self):
        self.first('POST', (r'/rest/v1/rpc/grant_hearts', Reply(200, None)))
        with paid():
            self.blocked('E-EDGE-22', '준비')
        self.assertEqual(self.sent_to('POST', '/me/avatar/regenerate'), [])
        self.assertNotIn('E-EDGE-22', area2_phone3._PAID)


if __name__ == '__main__':
    unittest.main()
