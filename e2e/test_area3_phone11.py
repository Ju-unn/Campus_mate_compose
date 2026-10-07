"""영역 3 신뢰 확인 6개(E-CHAT-37 · 38 · 39 · 40 · 41 · 44)의 PC 쪽 시험 — 폰 · 에뮬 · 운영 없이 가짜 앱 · 가짜 서버 · 가짜 알림창으로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area3_phone11`.

가짜 서버(test_area3.Fake)는 표만 들고 있어 신뢰 수락 API(`POST /chat/matches/{id}/trust`)와 방 머리말은 이 파일이 [Trust.serve_trust] 로 단다 —
서버(chat/router.py:295-340)와 같게: 수락 한 줄 · 수락 줄 · (둘 다면) 도장. 올바른 서버면 pass, 어긋난 서버(도장을 안 찍음 · 수락 줄을 두 번 넣음)면 fail 이어야 한다.
계정은 만든 순서대로 id-1(폰 계정) · id-2(상대) …, 토큰은 tok-1 ….
"""

import re
import threading
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock

from e2e import area1, area2_two_accept, area3, area3_phone11, notify, tools, twodev
from e2e.test_area3_phone import said
from e2e.test_area3_phone2 import MidwayApp, Phone2, as_fn
from e2e.test_area4_push import ACCEPT, CTL, ME, PARTNER, PUBLIC, TRUST, PushBase
from e2e.tools import Blocked, Reply

LINE = '{}님이 카카오톡 아이디·실사진 공개를 수락했어요'


def now():
    return datetime.now(timezone.utc)


class Trust(Phone2):
    """신뢰 확인 가짜 서버 — 계정 id-N 의 닉네임은 [nick](N), 수락한 줄은 messages(kind=trust_accept)."""

    def serve_trust(self, stamp=True, lines=1, leave_gate=True):
        def trust(sent):
            match_id, who = sent['path'].split('/')[3], sent['auth'].replace('tok-', 'id-')
            mine = self.rows('match_participants', match_id=match_id, profile_id=who)
            if any(r.get('trust_response') for r in mine):
                return Reply(409, {'detail': '이미 응답했어요'})
            mine[0].update(trust_response='accept', responded_at=now().isoformat())
            for _ in range(lines):
                self.put('messages', match_id=match_id, sender_id=who, kind='trust_accept',
                         body=LINE.format(self.nick(int(who[3:]))), created_at=now().isoformat())
            both = all(r.get('trust_response') == 'accept' for r in self.rows('match_participants', match_id=match_id))
            if both and stamp:
                self.rows('matches', id=match_id)[0]['trust_passed_at'] = now().isoformat()
            return Reply(200, {'passed': both})

        def room(sent):
            match_id, who = sent['path'].split('/')[3], sent['auth'].replace('tok-', 'id-')
            mine = self.rows('match_participants', match_id=match_id, profile_id=who)[0]
            passed = self.rows('matches', id=match_id)[0].get('trust_passed_at')
            return Reply(200, {'gate': {'my_response': mine.get('trust_response'), 'passed': bool(passed)}})

        self.fake.on('POST', r'/chat/matches/[^/]+/trust', trust)
        if leave_gate:
            self.fake.on('GET', r'/chat/matches/[^/]+', room)


class AcceptLineTest(Trust):
    """E-CHAT-37 — 폰 계정이 B(방을 연 쪽), 상대 A 의 수락은 PC 가 API 로 한다."""

    def run37(self, answer):
        events = []
        return self.case('E-CHAT-37', answer, MidwayApp(as_fn(answer), 'ready', events)), events

    def seen(self, seconds, **extra):
        """앱이 방 뷰모델에서 그 수락 줄을 본 시각 = 서버가 찍은 시각 + [seconds]."""
        line = next(r for r in self.rows('messages') if r.get('kind') == 'trust_accept')
        return said(**{'loaded': True, 'lines': [line['body']],
                       'seen_at': (datetime.fromisoformat(line['created_at']) + timedelta(seconds=seconds)).isoformat(), **extra})

    def test_37_the_partner_accepts_while_b_waits_and_the_line_shows_up_in_time(self):
        self.serve_trust()
        ((result, note), app), events = self.run37(lambda job: self.seen(1.2))
        self.assertEqual((result, note[:3]), ('pass', '지연 '), note)
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'nickname': self.nick(2), 'line': LINE.format(self.nick(2))}])
        self.assertEqual(events, ['step', 'go'])
        trusts = self.fake.by('POST', '/chat/matches/')
        self.assertEqual([s['auth'] for s in trusts], ['tok-2'])  # 상대(A)가 수락한다 — 폰 계정은 안 누른다
        self.assertEqual([(r['profile_id'], r.get('trust_response')) for r in self.rows('match_participants')],
                         [('id-1', None), ('id-2', 'accept')])
        self.assert_all_home()

    def test_37_fails_when_the_line_is_slow_missing_or_worded_differently(self):
        self.serve_trust()
        for label, answer in (('2.5초', lambda job: self.seen(2.5)), ('줄 없음', lambda job: self.seen(1.0, lines=[])),
                              ('다른 문구', lambda job: self.seen(1.0, lines=['누군가 수락했어요'])),
                              ('시각 없음', lambda job: said(loaded=True, lines=[LINE.format(self.nick(2))])),
                              ('깨진 시각', lambda job: self.seen(1.0, seen_at='not a time'))):
            (result, note), _ = self.run37(answer)[0]
            self.assertEqual(result, 'fail', f'{label}: {note}')

    def test_37_a_negative_delay_is_a_clock_difference_not_a_verdict(self):
        self.serve_trust()
        ((result, note), _), _ = self.run37(lambda job: self.seen(-3.0))
        self.assertEqual(result, 'pass', note)
        self.assertIn('시계 차', note)

    def test_37_a_room_that_never_loaded_is_blocked_and_nothing_is_accepted(self):
        self.serve_trust()  # 실제 앱은 방을 못 읽으면 step 을 안 부른다 — 그래서 멈춤 없는 가짜 앱
        (result, note), _ = self.case('E-CHAT-37', said(loaded=False, error=None, seen_at=None, lines=[]))
        self.assertEqual(result, 'blocked', note)
        self.assertIn('안 읽힘', note)
        self.assertEqual(self.fake.by('POST', '/chat/matches/'), [])

    def test_37_a_server_that_leaves_two_accept_lines_is_a_fail(self):
        self.serve_trust(lines=2)
        ((result, note), _), _ = self.run37(lambda job: self.seen(1.0))
        self.assertEqual(result, 'fail', note)
        self.assertIn('수락 줄', note)

    def test_37_the_waiting_banner_state_of_a_is_read_from_the_room_header(self):
        """A 의 "수락했어요. 상대의 응답을 기다리고 있어요" 배너는 머리말 gate.my_response=accept · passed=false 로 정해진다 — 그 값을 A 토큰으로 읽는다."""
        self.serve_trust()
        self.run37(lambda job: self.seen(1.0))
        reads = [s for s in self.fake.by('GET', '/chat/matches/')]
        self.assertEqual([s['auth'] for s in reads], ['tok-2'])

    def test_37_a_waiting_state_that_is_not_accept_is_a_fail(self):
        self.serve_trust(leave_gate=False)
        self.fake.on('GET', r'/chat/matches/[^/]+', Reply(200, {'gate': {'my_response': None, 'passed': False}}))
        ((result, note), _), _ = self.run37(lambda job: self.seen(1.0))
        self.assertEqual(result, 'fail', note)
        self.assertIn('기다림', note)


class AlertTest(PushBase):
    """E-CHAT-38 · 40 · 41 — 받는 사람은 폰 계정(tok-1), 상대(tok-2)가 API 로 수락한다. 가짜 알림창은 PushBase 의 World: 시험이 정한 API 가 불리면 알림이 뜬다."""

    def nick_of(self, token):
        return ([ME, PARTNER, CTL] + [f'Ex{i}' for i in range(9)])[int(token.removeprefix('tok-')) - 1]

    def caller(self):
        return self.world.callers[-1][2]

    def public(self, nick):
        return f'{nick} 님의 프로필이 공개됐어요'

    def passed(self, at='2026-10-05T03:00:00+00:00'):
        return [('GET', 'matches?', lambda b, u: Reply(200, [{'trust_passed_at': at}]))]

    def trust_alerts(self, off=()):
        """/trust 가 불리면 부른 사람 닉네임으로 수락 알림, 둘째 수락(통과)이면 공개 알림도(스위치 match_made 를 [off] 에 주면 안 뜬다)."""
        self.accepts = []

        def make(body, url):
            who = self.caller()
            self.accepts.append(who)
            made = [(self.nick_of(who), TRUST)]
            if len(self.accepts) % 2 == 0 and 'match_made' not in off:
                made.append((PUBLIC, self.public(self.nick_of(who))))
            return made
        self.world.on('POST', '/trust', make)

    def test_38_the_accept_arrives_as_a_message_when_the_switch_is_on_and_is_silent_when_off(self):
        switched = []
        self.world.on('PATCH', '/cards/notification-settings', lambda b, u: switched.append((self.caller(), b)) or [])

        def trust(body, url):  # 받는 사람 = 부른 사람 − 1(짝수 토큰이 상대)
            caller = self.caller()
            receiver = f'tok-{int(caller.removeprefix("tok-")) - 1}'
            return [] if (receiver, {'new_message': False}) in switched else [(self.nick_of(caller), TRUST)]
        self.world.on('POST', '/trust', trust)
        self.world.on('POST', '/decision', lambda b, u: [(ACCEPT, f'{self.nick_of(self.caller())} 님이 대화를 하고 싶어 해요')])
        result = self.go_push('E-CHAT-38')
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(switched, [('tok-3', {'new_message': False})])  # 끈 판의 받는 사람(둘째 판의 폰 계정)만
        trusts = [who for m, path, who in self.world.callers if m == 'POST' and '/trust' in path]
        self.assertEqual(trusts, ['tok-2', 'tok-4'])  # 두 판 모두 상대가 수락

    def test_38_a_missing_or_doubled_accept_notification_when_on_is_a_fail(self):
        self.world.on('POST', '/decision', lambda b, u: [(ACCEPT, f'{self.nick_of(self.caller())} 님이 대화를 하고 싶어 해요')])
        self.assertEqual(self.go_push('E-CHAT-38')[0], 'fail')  # 켠 판인데 안 옴
        self.world.reset()
        self.world.on('POST', '/trust', lambda b, u: [(self.nick_of(self.caller()), TRUST)] * 2)
        self.assertEqual(self.go_push('E-CHAT-38')[0], 'fail')  # 두 개

    def test_38_a_notification_that_comes_with_the_switch_off_is_a_fail(self):
        self.world.on('POST', '/trust', lambda b, u: [(self.nick_of(self.caller()), TRUST)])
        self.world.on('POST', '/decision', lambda b, u: [(ACCEPT, f'{self.nick_of(self.caller())} 님이 대화를 하고 싶어 해요')])
        result = self.go_push('E-CHAT-38')
        self.assertEqual(result[0], 'fail')
        self.assertIn('안 와야 할 알림', result[1])

    def test_38_without_the_control_notification_the_silence_is_not_believed(self):
        self.world.on('PATCH', '/cards/notification-settings', lambda b, u: [])
        self.world.on('POST', '/trust', lambda b, u: [(self.nick_of(self.caller()), TRUST)] if self.caller() == 'tok-2' else [])
        self.assertEqual(self.go_push('E-CHAT-38')[0], 'blocked')

    def test_40_the_last_accept_gives_the_phone_the_public_notification_once_and_the_row_is_stamped(self):
        self.trust_alerts()
        result = self.go_push('E-CHAT-40', self.passed())
        self.assertEqual(result[0], 'pass', result)
        trusts = [who for m, path, who in self.world.callers if m == 'POST' and '/trust' in path]
        self.assertEqual(trusts, ['tok-1', 'tok-2'])  # 폰 계정이 먼저, 상대가 마지막
        self.assertEqual(self.fake.bodies('PATCH', '/cards/notification-settings'), [])

    def test_40_a_missing_doubled_or_unstamped_public_notification_is_a_fail(self):
        self.trust_alerts(off=('match_made',))
        self.assertEqual(self.go_push('E-CHAT-40', self.passed())[0], 'fail')  # 안 옴
        self.world.reset()
        self.world.on('POST', '/trust', lambda b, u: [(PUBLIC, self.public(PARTNER))] * 2 if self.caller() == 'tok-2' else [])
        self.assertEqual(self.go_push('E-CHAT-40', self.passed())[0], 'fail')  # 두 개
        self.world.reset()
        self.trust_alerts()
        result = self.go_push('E-CHAT-40', self.passed(None))
        self.assertEqual(result[0], 'fail')  # 알림은 왔지만 도장이 없다
        self.assertIn('trust_passed_at', result[1])

    def test_41_with_match_made_off_only_the_message_notification_comes_and_the_row_is_still_stamped(self):
        self.world.on('POST', '/trust', lambda b, u: [(PARTNER, TRUST)] if self.caller() == 'tok-2' else [])  # 새 메시지 알림은 온다 — 대조를 겸한다
        result = self.go_push('E-CHAT-41', self.passed())
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.fake.bodies('PATCH', '/cards/notification-settings'), [{'match_made': False}])

    def test_41_a_public_notification_with_the_switch_off_is_a_fail(self):
        self.world.on('POST', '/trust', lambda b, u: [(PARTNER, TRUST), (PUBLIC, self.public(PARTNER))] if self.caller() == 'tok-2' else [])
        self.assertEqual(self.go_push('E-CHAT-41', self.passed())[0], 'fail')

    def test_41_a_silence_without_the_message_notification_or_the_stamp_is_not_a_pass(self):
        self.assertEqual(self.go_push('E-CHAT-41', self.passed())[0], 'blocked')  # 길이 살아 있는지 모른다
        self.world.reset()
        self.world.on('POST', '/trust', lambda b, u: [(PARTNER, TRUST)] if self.caller() == 'tok-2' else [])
        result = self.go_push('E-CHAT-41', self.passed(None))
        self.assertEqual(result[0], 'fail')  # 안 온 것이 통과 때문이 아니라 통과가 안 돼서일 수 있다
        self.assertIn('trust_passed_at', result[1])

    def test_the_three_cases_need_daylight_and_the_push_connection_check(self):
        for case in ('E-CHAT-38', 'E-CHAT-40', 'E-CHAT-41'):
            with self.subTest(case=case), mock.patch.object(notify, 'require_daytime', mock.Mock(side_effect=Blocked('밤'))):
                result = self.go_push(case)
                self.assertEqual(result[0], 'blocked')
                self.assertEqual(self.phone.jobs, [])


# ── 두 기기 — E-CHAT-39 · 44 ─────────────────────────────────────────────────────────────────────────

KAKAO = {'id-1': 'e2e-kakao-a', 'id-2': 'e2e-kakao-b'}
PHOTO = {'id-1': 'id-1/photo0.png', 'id-2': 'id-2/photo0.png'}
STORAGE = 'https://x.supabase.co/storage/v1'
WAITING = '수락했어요. 상대의 응답을 기다리고 있어요'
PRE_ACCEPT = '카카오톡 아이디를 먼저 공유해도 돼요'


def signed(who, token='tk'):
    return f'{STORAGE}/object/sign/profile-photos/{PHOTO[who]}?token={token}'


class FakeTwo:
    """twodev.bound 가 주는 `two` 대신 — script 의 한 줄 `(쪽, step, 앱이 step 에 실은 값, go 를 받은 뒤 앱이 서버에 남기는 일)` 을 차례로, 줄이 목록이면 한꺼번에(스레드) 돌린다.
    핸들러가 던진 예외는 그 쪽이 blocked 로 끝난 것이다(twodev._side 와 같다) — 그러면 그 뒤의 일(앱이 누름)은 일어나지 않고, 결과를 ('blocked', …) 로 바꾼다."""

    def __init__(self, test, script, result=('pass', 'A: pass  B: pass')):
        self.test, self.script, self.result = test, script, result
        self.went, self.errors, self.limit, self.a_job, self.b_job, self.before = {}, [], None, None, None, None

    def __call__(self, plan, a_job=None, b_job=None, **limit):
        self.a_job, self.b_job, self.limit = a_job, b_job, limit
        self.before = len(self.test.fake.by('POST', '/chat/matches/'))  # 앱이 켜지기 전에 PC 가 서버에 한 수락 수
        groups = [g if isinstance(g, list) else [g] for g in self.script]
        self.plan_keys = sorted(plan)
        self.test.assertTrue({(side, step) for group in groups for side, step, _, _ in group} <= set(plan), '앱이 말하는 step 에 핸들러가 없다')
        sync = twodev.Sync()

        def play(entry):
            side, step, extra, after = entry
            try:
                self.went[(side, step)] = plan[(side, step)]({'step': step, 't': 0, **extra}, sync)
                if after:
                    after()
            except Exception as e:
                self.errors.append((side, step, e))

        for group in groups:
            threads = [threading.Thread(target=play, args=(entry,)) for entry in group]
            for t in threads:
                t.start()
            for t in threads:
                t.join(5)
        if self.errors:
            return 'blocked', '; '.join(f'{side}/{step}: {e}' for side, step, e in self.errors)
        return self.result


class TwoTrust(Trust):
    def setUp(self):
        super().setUp()
        for patcher in (mock.patch.object(area2_two_accept, 'PEER', 0.3), mock.patch.object(area2_two_accept, 'SAVED', 0.05),
                        mock.patch.object(area2_two_accept, 'POLL', 0)):
            patcher.start()
            self.addCleanup(patcher.stop)
        self.fresh()

    def fresh(self, **trust):
        """같은 시험 안에서 서버를 처음 상태로 — 계정 · 표 · 신뢰 수락 API(옵션 [trust] 는 serve_trust)를 다시 놓는다."""
        self.fake.tables.clear()
        self.fake.sent.clear()
        self.fake.statuses.clear()
        self.fake.users.clear()
        self.fake.handlers.clear()
        self.fake.verifies = self.fake._ids = 0
        self.fake.tables['profile_private'] = [{'profile_id': who, 'kakao_id': kakao} for who, kakao in KAKAO.items()]
        self.fake.tables['profile_photos'] = [{'profile_id': who, 'storage_path': path, 'position': 0} for who, path in PHOTO.items()]
        self.fake.tables['profile_photos'].append({'profile_id': 'id-1', 'storage_path': 'id-1/photo1.png', 'position': 1})
        self.serve_trust(**trust)

    def go(self, case, *script, result=('pass', 'A: pass  B: pass')):
        self.two = FakeTwo(self, script, result)
        return twodev.TWO[case](self.run_, self.two)

    def press(self, who, at=None):
        """앱이 확인 창의 "수락" 을 누른 일 — 서버에 수락이 가고(응답 시각 [at] 이 있으면 그 시각으로 찍힌다)."""
        def after():
            mid = self.match()
            status, _ = tools.api(self.run_.cfg, 'POST', f'/chat/matches/{mid}/trust', f'tok-{who}')
            self.assertEqual(status, 200)
            if at:
                self.rows('match_participants', match_id=mid, profile_id=f'id-{who}')[0]['responded_at'] = at.isoformat()
        return after

    def card(self, other, ms=900, **over):
        """앱이 "신뢰 확인 완료" 카드를 본 말 — [other] 는 상대(카드에 나오는 사람)의 id 번호."""
        who = f'id-{other}'
        return {'loaded': True, 'card': True, 'card_ms': ms, 'kakao_id': KAKAO[who], 'kakao_shown': True,
                'photos': [signed(who)], 'header_photo': signed(who, 'other'), 'error': None, **over}

    def banners(self, *titles):
        return {'loaded': True, 'banners': list(titles)}


class BothScreensTest(TwoTrust):
    """E-CHAT-39 — A(폰)는 PC 가 API 로 미리 수락해 두고 기다림 배너로 방에서 기다린다. B(에뮬)가 화면에서 수락한다."""

    def ok(self, **a_over):
        return [('A', 'ready', self.banners(WAITING), None), ('B', 'armed', self.banners(PRE_ACCEPT), self.press(2)),
                ('A', 'report', self.card(2, **a_over), None), ('B', 'report', self.card(1), None)]

    def test_39_both_screens_get_the_card_the_kakao_id_and_the_real_photo(self):
        result, memo = self.go('E-CHAT-39', *self.ok())
        self.assertEqual(result, 'pass', memo)
        self.assertIn('900ms', memo)
        self.assertEqual(self.two.before, 1)  # A 의 수락은 앱을 켜기 전에 PC 가 한다("E-CHAT-37 뒤")
        self.assertEqual([s['auth'] for s in self.fake.by('POST', '/chat/matches/')], ['tok-1', 'tok-2'])
        self.assertEqual(self.two.a_job, {'token_hash': 'h', 'nickname': self.nick(2)})
        self.assertEqual(self.two.b_job, {'token_hash': 'h', 'nickname': self.nick(1)})
        self.assertEqual(self.two.limit, area3_phone11.LIMITS)
        self.assertEqual(self.two.plan_keys, [('A', 'ready'), ('A', 'report'), ('B', 'armed'), ('B', 'report')])

    def test_39_b_waits_for_a_to_be_ready_so_the_listener_is_set_before_the_accept(self):
        self.go('E-CHAT-39', *self.ok())
        self.assertEqual(self.two.went[('A', 'ready')], None)
        self.assertEqual(self.two.went[('B', 'armed')], None)

    def test_39_fails_when_a_sees_the_card_late_or_never_saw_the_line(self):
        for label, over in (('2.5초', {'ms': 2500}), ('줄을 못 봄', {'card_ms': None})):
            ms = over.pop('ms', 900)
            result, memo = self.go('E-CHAT-39', *self.ok(ms=ms, **over))
            self.assertEqual(result, 'fail', f'{label}: {memo}')
            self.assertTrue('2.0' in memo or '수락 줄' in memo, memo)
            self.fresh()

    def test_39_fails_on_a_wrong_kakao_id_or_one_not_shown(self):
        for label, over, word in (('다른 아이디', {'kakao_id': 'other'}, '카카오톡 아이디'), ('안 보임', {'kakao_shown': False}, '안 보임')):
            result, memo = self.go('E-CHAT-39', *self.ok(**over))
            self.assertEqual(result, 'fail', f'{label}: {memo}')
            self.assertIn(word, memo)
            self.fresh()

    def test_39_fails_when_the_head_photo_is_not_the_real_photo_of_the_partner(self):
        avatar = f'{STORAGE}/object/public/avatars/id-2/a.png'
        for label, over in (('아바타 그대로', {'header_photo': avatar}), ('남의 사진', {'header_photo': signed('id-1')}),
                            ('머리 사진 없음', {'header_photo': None}), ('목록이 비었다', {'photos': []})):
            result, memo = self.go('E-CHAT-39', *self.ok(**over))
            self.assertEqual(result, 'fail', f'{label}: {memo}')
            self.assertIn('사진', memo)
            self.fresh()

    def test_39_a_second_screen_without_the_card_or_a_missing_waiting_banner_is_a_fail(self):
        script = self.ok()
        script[3] = ('B', 'report', self.card(1, card=False, card_ms=None), None)
        result, memo = self.go('E-CHAT-39', *script)
        self.assertEqual(result, 'fail', memo)
        self.assertIn('B 화면', memo)
        self.fresh()
        script = self.ok()
        script[0] = ('A', 'ready', self.banners(PRE_ACCEPT), None)
        result, memo = self.go('E-CHAT-39', *script)
        self.assertEqual(result, 'fail', memo)
        self.assertIn('기다림 배너', memo)

    def test_39_a_server_that_does_not_stamp_or_writes_a_third_line_is_a_fail(self):
        self.fresh(stamp=False)
        result, memo = self.go('E-CHAT-39', *self.ok())
        self.assertEqual(result, 'fail', memo)
        self.assertIn('trust_passed_at', memo)
        self.fresh(lines=2)
        result, memo = self.go('E-CHAT-39', *self.ok())
        self.assertEqual(result, 'fail', memo)
        self.assertIn('수락 줄', memo)

    def test_39_a_room_that_never_loaded_is_blocked_not_a_fail(self):
        script = self.ok()
        script[0] = ('A', 'ready', {'loaded': False, 'banners': []}, None)
        result, memo = self.go('E-CHAT-39', *script[:2])
        self.assertEqual(result, 'blocked', memo)
        self.assertEqual(len(self.fake.by('POST', '/chat/matches/')), 1)  # B 는 누르지 못했다

    def test_39_the_photo_and_kakao_id_must_exist_for_the_judgement(self):
        self.fake.tables['profile_photos'] = [r for r in self.fake.tables['profile_photos'] if r['profile_id'] != 'id-2']
        result, memo = self.go('E-CHAT-39', *self.ok())
        self.assertEqual(result, 'blocked', memo)
        self.assertEqual(self.two.went, {})  # 앱을 켜기 전에 막힌다


class SameMomentTest(TwoTrust):
    """E-CHAT-44 — 두 기기가 확인 창을 연 채 `armed` 에서 서고, 둘 다 선 뒤에 같이 누른다."""

    def at(self, ms):
        return datetime(2026, 10, 7, 3, 0, 0, tzinfo=timezone.utc) + timedelta(milliseconds=ms)

    def script(self, a_card=None, b_card=None, a_press=None, b_press=None):
        return [[('A', 'armed', self.banners(PRE_ACCEPT), a_press or self.press(1, self.at(0))),
                 ('B', 'armed', self.banners(PRE_ACCEPT), b_press or self.press(2, self.at(35)))],
                ('A', 'report', a_card or self.card(2, ms=700), None), ('B', 'report', b_card or self.card(1, ms=1100), None)]

    def test_44_one_stamp_two_lines_and_both_screens_get_the_card(self):
        result, memo = self.go('E-CHAT-44', *self.script())
        self.assertEqual(result, 'pass', memo)
        self.assertIn('35ms', memo)  # 서버가 받은 두 수락의 시각 차
        self.assertIn('700ms', memo)  # 두 화면이 공개되기까지
        self.assertIn('1100ms', memo)
        self.assertEqual(self.two.went[('A', 'armed')], None)
        self.assertEqual(self.two.limit, area3_phone11.LIMITS)
        self.assertEqual(self.two.plan_keys, [('A', 'armed'), ('A', 'report'), ('B', 'armed'), ('B', 'report')])
        self.assertEqual([r.get('trust_response') for r in self.rows('match_participants')], ['accept', 'accept'])

    def test_44_neither_side_is_released_before_both_are_armed(self):
        result, memo = self.go('E-CHAT-44', self.script()[0][0])  # B 가 안 서면 A 도 못 누른다
        self.assertEqual(result, 'blocked', memo)
        self.assertEqual([(side, step) for side, step, _ in self.two.errors], [('A', 'armed')])  # B 를 기다리다 상한 안에 못 만나 blocked
        self.assertEqual(self.fake.by('POST', '/chat/matches/'), [])  # A 는 풀리지 않아 누르지 못했다

    def test_44_both_accepted_but_nobody_stamped_is_blocked_as_a_defect_candidate_not_a_fail(self):
        self.fresh(stamp=False)
        result, memo = self.go('E-CHAT-44', *self.script(a_card=self.card(2, card=False, card_ms=None), b_card=self.card(1, card=False, card_ms=None)))
        self.assertEqual(result, 'blocked', memo)
        self.assertIn('결함 후보', memo)
        self.assertIn('trust_passed_at', memo)

    def test_44_a_stamp_with_a_screen_that_stays_on_the_waiting_banner_is_a_fail(self):
        result, memo = self.go('E-CHAT-44', *self.script(b_card=self.card(1, card=False, card_ms=None)))
        self.assertEqual(result, 'fail', memo)
        self.assertIn('B 화면', memo)

    def test_44_a_missing_accept_or_a_third_line_is_a_fail_even_with_no_stamp(self):
        self.fresh(stamp=False)
        result, memo = self.go('E-CHAT-44', *self.script(b_press=lambda: None))
        self.assertEqual(result, 'fail', memo)
        self.assertIn('accept', memo)
        self.fresh(lines=2)
        result, memo = self.go('E-CHAT-44', *self.script())
        self.assertEqual(result, 'fail', memo)
        self.assertIn('수락 줄', memo)

    def test_44_the_skew_note_says_what_it_could_not_guarantee(self):
        result, memo = self.go('E-CHAT-44', *self.script())
        self.assertIn('±50ms', memo)
        self.assertIn('보장', memo)

    def test_44_a_side_that_could_not_load_the_room_stops_the_other_at_once_instead_of_waiting_for_the_limit(self):
        script = [[('A', 'armed', {'loaded': False, 'error': '방 오류'}, self.press(1)), ('B', 'armed', self.banners(PRE_ACCEPT), self.press(2))]]
        result, memo = self.go('E-CHAT-44', *script)
        self.assertEqual(result, 'blocked', memo)
        self.assertIn('안 읽힘', memo)
        self.assertEqual(self.fake.by('POST', '/chat/matches/'), [])  # 둘 다 누르지 못했다

    def test_44_an_app_that_never_loaded_the_room_is_blocked_and_the_server_judgement_is_skipped(self):
        script = self.script(a_card={'loaded': False, 'card': False, 'card_ms': None})
        result, memo = self.go('E-CHAT-44', *script)
        self.assertEqual(result, 'blocked', memo)


class RegistryTest(unittest.TestCase):
    PHONE = ['E-CHAT-37', 'E-CHAT-38', 'E-CHAT-40', 'E-CHAT-41']
    TWO = ['E-CHAT-39', 'E-CHAT-44']

    def dart(self, name):
        return (tools.ROOT / 'frontend' / 'integration_test' / name).read_text(encoding='utf-8')

    def test_bundles_hold_the_four_phone_and_two_two_device_cases(self):
        self.assertEqual(area3.BUNDLES['area3-phone-11'], self.PHONE)
        self.assertEqual(area1.BUNDLES['area3-two-11'], self.TWO)
        for case in self.PHONE:
            self.assertIn(case, area1.PHONE)
            self.assertNotIn(case, twodev.TWO)
        for case in self.TWO:
            self.assertIn(case, twodev.TWO)
            self.assertNotIn(case, area1.PHONE)

    def test_each_number_is_registered_in_this_module_only(self):
        pieces = sorted(path.name for path in (tools.ROOT / 'e2e').glob('*.py') if not path.name.startswith('test_')
                        and any(f"'{case}':" in path.read_text(encoding='utf-8') for case in self.PHONE + self.TWO))
        self.assertEqual(pieces, ['area3_phone11.py'])

    def test_the_time_limits_cover_the_accounts_and_the_waits(self):
        account = area3_phone11.ACCOUNT
        for case in ('E-CHAT-39', 'E-CHAT-44'):  # 계정 둘 + 두 기기가 서로 기다리는 전체 상한
            self.assertGreaterEqual(tools.CASE_LIMITS[case], area3_phone11.LIMITS['deadline'] + 2 * account, case)
        self.assertGreaterEqual(tools.CASE_LIMITS['E-CHAT-38'], 5 * account)  # 두 판 — 계정 5(폰 둘 · 상대 둘 · 대조 하나)
        for case in ('E-CHAT-40', 'E-CHAT-41'):  # 계정 둘 + 알림 기다림(60 + 20) + 대조(30) + 앱 켜기
            self.assertGreaterEqual(tools.CASE_LIMITS[case], 2 * account + 60 + 20 + 30 + 60, case)
        self.assertGreaterEqual(tools.CASE_LIMITS['E-CHAT-37'], 2 * account + 180)
        self.assertEqual(area3_phone11.LIMITS, {'side_timeout': {'A': 300, 'B': 300}, 'deadline': 720})

    def test_main_registers_the_module_after_phone8_and_before_the_bundle_table(self):
        from e2e import __main__ as main
        text = Path(main.__file__).read_text(encoding='utf-8')
        line = 'from e2e import area3_phone11  # noqa: F401'
        self.assertIn(line, text)
        self.assertLess(text.index('from e2e import area3_phone8'), text.index(line))
        self.assertLess(text.index(line), text.index('BUNDLES = {'))
        self.assertEqual(main.BUNDLES['area3-phone-11'], self.PHONE)
        self.assertEqual(main.BUNDLES['area3-two-11'], self.TWO)
        self.assertFalse(set(self.PHONE + self.TWO) & set(main.API_CASES))

    def test_the_app_part_is_wired_into_area3_in_the_agreed_shape(self):
        area3_dart = self.dart('area3.dart')
        self.assertIn("part 'area3_b11.dart';\n", area3_dart)
        self.assertIn('  ...area3Cases11,\n', area3_dart)
        self.assertLess(area3_dart.index("part 'area3_b8.dart';"), area3_dart.index("part 'area3_b11.dart';"))
        self.assertLess(area3_dart.index('  ...area3Cases8,'), area3_dart.index('  ...area3Cases11,'))
        self.assertTrue(self.dart('area3_b11.dart').startswith("part of 'area3.dart';"))

    def test_the_app_has_every_key_and_every_step_the_pc_waits_for(self):
        dart = self.dart('area3_b11.dart')
        for key in ('E-CHAT-37', 'E-CHAT-38', 'E-CHAT-39/A', 'E-CHAT-39/B', 'E-CHAT-40', 'E-CHAT-41', 'E-CHAT-44/A', 'E-CHAT-44/B'):
            self.assertRegex(dart, rf"(?m)^  '{re.escape(key)}':", key)
        for name in ('ready', 'armed', 'report'):
            self.assertRegex(dart, rf"_trStep\('{name}'", name)
        self.assertRegex(dart, r"step\('ready'\)")  # E-CHAT-37 은 support.step

    def test_every_top_level_name_in_the_app_part_is_ours(self):
        dart = self.dart('area3_b11.dart')
        # 줄 맨 앞(들여쓰기 없음)에서 시작하는 선언: [const|final] [타입] 이름 = … 또는 [타입] 이름(…
        names = re.findall(r'(?m)^(?=\w)(?:const |final )?(?:[\w<>?, ]+? )?(\w+)(?: =|\()', dart)
        self.assertGreaterEqual(len(names), 13)  # 상수 3 + 함수 9 + 맵 1 — 못 읽으면 아래 반복이 비어 헛통과한다
        self.assertIn('area3Cases11', names)
        for name in names:
            self.assertTrue(name.startswith('_tr') or name == 'area3Cases11', name)

    def test_the_app_reports_through_the_step_that_carries_values(self):
        dart = self.dart('area3_b11.dart')
        self.assertIn("say({'step': name, ...data})", dart)  # support.step 은 값을 못 싣는다 — 그래서 직접 말한다


if __name__ == '__main__':
    unittest.main()
