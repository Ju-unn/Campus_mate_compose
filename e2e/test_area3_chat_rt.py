"""영역 3 실시간 · 화면 가설 10개(E-CHAT-01 · 02 · 03 · 07 · 22 · 23 · 24 · 58 · 61 · 72)의 PC 쪽 시험 — 폰 · 에뮬 · 운영 없이 가짜 앱 · 가짜 서버로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area3_chat_rt`.

가짜 서버는 test_area3_phone8 의 Phone8(채팅 보내기 · 읽기 · 나가기)에 신뢰 수락 · 대화 목록을 더했다. 올바른 서버면 pass, 어긋난 서버(나가도 방이 목록에 남음 …)나
어긋난 앱 말(2초 넘게 걸림 · 순서가 다름 · 배너도 글도 없음)이면 fail 이어야 한다. 두 기기 가설은 가짜 `two`([Script])가 앱이 말하는 차례대로 PC 핸들러를 부른다.
가짜 앱은 폰 가설용 [MidwayApp](step 한 번) · [StepsApp](step 여러 번). 계정은 만든 순서대로 id-1 · id-2 …, 토큰은 tok-1 …
"""

import re
import unittest
from datetime import datetime, timedelta, timezone
from unittest import mock

from e2e import area1, area3, area3_chat_rt, notify, tools, twodev
from e2e.test_area3_phone import App, said
from e2e.test_area3_phone2 import MidwayApp, as_fn
from e2e.test_area3_phone8 import Phone8
from e2e.tools import Reply, Run

PEER_SECONDS = area3_chat_rt.PEER  # TwoBase 가 시험 동안 0.05 로 낮추기 전의 진짜 값
PHONE = ['E-CHAT-01', 'E-CHAT-02', 'E-CHAT-07', 'E-CHAT-22', 'E-CHAT-23', 'E-CHAT-24', 'E-CHAT-61', 'E-CHAT-72']
TWO = ['E-CHAT-03', 'E-CHAT-58']
NETWORK_AIRPLANE = ('shell', 'cmd', 'connectivity', 'airplane-mode')
GONE_NOTICE = '상대가 채팅방을 나가 더 이상 메시지를 보낼 수 없어요.'


def now():
    return datetime.now(timezone.utc)


def stamp(at):
    return at.isoformat().replace('+00:00', 'Z')  # 앱(Dart toUtc().toIso8601String())이 말하는 모양


class FakeHub:
    """stepper 가 두 번째 멈춤부터 쓰는 우편함 — go 를 남기고 다음 step 을 돌려준다."""

    def __init__(self, steps, events):
        self.steps, self.events = list(steps), events

    def go(self, extra=None):
        self.events.append('go')

    def wait(self, timeout):
        self.events.append('step')
        return {'step': self.steps.pop(0)} if self.steps else {'result': 'pass'}


class StepsApp(MidwayApp):
    """앱이 step 을 [steps] 만큼 차례로 말하고 멈추는 것 — 첫 멈춤은 midway, 나머지는 stepper 가 hub 로 듣는다."""

    def __init__(self, answer, steps, events):
        super().__init__(answer, steps[0], events)
        self.rest, self.hub = steps[1:], FakeHub(steps[1:], events)

    def __call__(self, midway=None, **job):
        self.hub.steps = list(self.rest)  # 앱을 다시 켤 때마다(판마다) 같은 차례로
        return super().__call__(midway, **job)


class Phone9(Phone8):
    def setUp(self):
        super().setUp()
        self.events = []
        self.serve_chat()
        self.fake.on('POST', r'/chat/matches/[^/]+/trust', self.trust)
        self.fake.on('GET', r'/chat/conversations', self.conversations)

    # ── 가짜 서버 ────────────────────────────────────────────────────────────────────────────────────

    def trust(self, sent):
        match_id = sent['path'].split('/')[3]
        for row in self.rows('match_participants', match_id=match_id, profile_id=self.who(sent)):
            row['trust_response'] = 'accept'
        if all(p.get('trust_response') == 'accept' for p in self.rows('match_participants', match_id=match_id)):
            for match in self.rows('matches', id=match_id):
                match['trust_passed_at'] = now().isoformat()
        return Reply(200, {'passed': True})

    def conversations(self, sent):
        mine = [p['match_id'] for p in self.rows('match_participants', profile_id=self.who(sent)) if not p.get('left_at')]
        return Reply(200, {'conversations': [{'match_id': m} for m in mine]})

    def run_case(self, name, answer, app=None):
        return self.case(name, answer, app or MidwayApp(as_fn(answer), 'go', self.events))

    # ── 앱이 한 말 만들기 ────────────────────────────────────────────────────────────────────────────

    def created(self):
        """글 본문 → 서버가 찍은 시각(DB)."""
        return {m['body']: datetime.fromisoformat(m['created_at']) for m in self.rows('messages', kind='text')}

    def seen_after(self, delays, bodies=None):
        """앱 시계 = 서버가 찍은 시각 + [delays](초 · 목록 또는 하나)."""
        made = self.created()
        bodies = bodies or [b for b in made]
        delays = delays if isinstance(delays, (list, tuple)) else [delays] * len(bodies)
        return {body: stamp(made[body] + timedelta(seconds=delay)) for body, delay in zip(bodies, delays)}

    def bodies_of(self, job):
        return job['bodies']


# ── E-CHAT-01 · 02 ───────────────────────────────────────────────────────────────────────────────────

class StreamTest(Phone9):
    def good(self, delays=0.8, **override):
        def answer(job):
            made = self.created()
            order = sorted(made, key=made.get)
            return said(loaded=True, seen=self.seen_after(delays, job['bodies']), order=order, bubble_last=True, **override)
        return answer

    def test_01_partner_a_sends_twenty_three_seconds_apart_and_the_phone_as_b_shows_each_in_time(self):
        (result, note), app = self.run_case('E-CHAT-01', self.good())
        self.assertEqual(result, 'pass', note)
        job = app.jobs[0]
        self.assertEqual(set(job), {'token_hash', 'nickname', 'bodies'})
        self.assertEqual(job['nickname'], self.nick(1))  # 폰 계정(B)은 큰 id 인 id-2 — 상대 A 는 id-1
        self.assertEqual(len(job['bodies']), 20)
        self.assertTrue(all(re.fullmatch(r'E2E-01-\d\d-[0-9a-f]+', b) for b in job['bodies']))
        self.assertEqual(len(set(job['bodies'])), 20)  # 매번 다른 본문
        self.assertEqual(self.events, ['step', 'go'])
        sends = self.fake.by('POST', '/chat/matches/')
        self.assertEqual([s['body']['body'] for s in sends], job['bodies'])  # 순번 차례대로
        self.assertEqual({s['auth'] for s in sends}, {'tok-1'})
        self.assert_pair(self.match(), 'id-1', 'id-2')
        self.assert_all_home()

    def test_02_the_phone_is_a_the_smaller_id_and_b_sends(self):
        """matches 는 profile_a < profile_b 로 저장된다 — 01 은 폰이 큰 id(B), 02 는 작은 id(A)."""
        (result, note), app = self.run_case('E-CHAT-02', self.good())
        self.assertEqual(result, 'pass', note)
        job = app.jobs[0]
        self.assertEqual(job['nickname'], self.nick(2))  # 폰 계정(A)은 작은 id 인 id-1 — 상대 B 는 id-2
        self.assertTrue(all(re.fullmatch(r'E2E-02-\d\d-[0-9a-f]+', b) for b in job['bodies']))
        self.assertEqual({s['auth'] for s in self.fake.by('POST', '/chat/matches/')}, {'tok-2'})

    def test_three_seconds_between_sends_are_laid_out_from_the_first_send(self):
        slept = []
        with mock.patch('time.sleep', side_effect=slept.append):
            self.run_case('E-CHAT-01', self.good())
        waits = [s for s in slept if s > 0]
        self.assertEqual(len(waits), 19)  # 첫 글은 바로, 나머지 19번은 첫 보내기에서 센 3초 칸(3 · 6 · … · 57초 지점)까지 기다린다
        self.assertTrue(all(abs(w - area3_chat_rt.GAP * i) < 1.0 for i, w in enumerate(waits, start=1)), waits)
        self.assertEqual(area3_chat_rt.GAP, 3.0)
        self.assertEqual(area3_chat_rt.STREAM, 20)

    def test_the_memo_lists_every_delay_with_max_mean_and_95th(self):
        (result, note), _ = self.run_case('E-CHAT-01', self.good([0.5 + i * 0.05 for i in range(20)]))
        self.assertEqual(result, 'pass', note)
        self.assertIn('최대 1.45초', note)
        self.assertIn('평균 0.97초', note)
        self.assertIn('95번째 1.40초', note)
        self.assertIn('20:1.45', note)  # 메시지마다 걸린 시간 표(순번:초)
        self.assertIn('1:0.50', note)

    def test_fails_when_one_message_takes_over_two_seconds(self):
        delays = [0.7] * 20
        delays[6] = 2.4
        (result, note), _ = self.run_case('E-CHAT-01', self.good(delays))
        self.assertEqual(result, 'fail')
        self.assertIn('7:2.4', note)

    def test_exactly_two_seconds_is_still_in_time(self):
        (result, note), _ = self.run_case('E-CHAT-02', self.good(2.0))
        self.assertEqual(result, 'pass', note)

    def test_negative_delays_are_a_clock_difference_and_are_left_out_of_the_judgement(self):
        delays = [0.7] * 20
        delays[0], delays[1] = -3.0, -3.0
        (result, note), _ = self.run_case('E-CHAT-01', self.good(delays))
        self.assertEqual(result, 'pass', note)
        self.assertIn('음수 2건', note)
        self.assertIn('시계 차', note)
        self.assertIn('18건', note)  # 판정에 쓴 것은 나머지 18건
        (result, note), _ = self.run_case('E-CHAT-01', self.good([3.0 * i - 1.0 if i < 2 else 2.9 for i in range(20)]))
        self.assertEqual(result, 'fail', note)  # 음수를 빼도 2.9초는 남는다

    def test_when_fewer_than_half_can_be_judged_the_clock_difference_blocks_the_case(self):
        (result, note), _ = self.run_case('E-CHAT-01', self.good(-5.0))
        self.assertEqual(result, 'blocked', note)
        self.assertIn('시계 차로 판정 불가', note)

    def test_exactly_half_judgeable_still_judges_and_one_less_blocks(self):
        for negatives, want in ((10, 'pass'), (11, 'blocked')):
            delays = [-2.0] * negatives + [0.7] * (20 - negatives)
            (result, note), _ = self.run_case('E-CHAT-01', self.good(delays))
            self.assertEqual(result, want, (negatives, note))

    def test_a_fail_the_pc_found_wins_over_the_clock_block(self):
        (result, note), _ = self.run_case('E-CHAT-01', lambda job: {**self.good(-5.0)(job), 'bubble_last': False})
        self.assertEqual(result, 'fail', note)

    def test_fails_on_a_message_the_screen_never_got_or_a_time_that_cannot_be_read(self):
        def partial(job):
            seen = self.seen_after(0.5, job['bodies'])
            del seen[job['bodies'][3]]
            return said(loaded=True, seen=seen, order=job['bodies'], bubble_last=True)
        (result, note), _ = self.run_case('E-CHAT-01', partial)
        self.assertEqual(result, 'fail')
        self.assertIn('4번', note)
        (result, note), _ = self.run_case('E-CHAT-01', lambda job: said(loaded=True, seen={b: 'not a time' for b in job['bodies']},
                                                                          order=job['bodies'], bubble_last=True))
        self.assertEqual(result, 'fail')

    def test_fails_when_the_screen_order_or_the_last_bubble_is_wrong(self):
        good = self.good()
        (result, note), _ = self.run_case('E-CHAT-01', lambda job: {**good(job), 'bubble_last': False})
        self.assertEqual((result, '말풍선' in note), ('fail', True))
        (result, note), _ = self.run_case('E-CHAT-01', lambda job: {**good(job), 'order': list(reversed(good(job)['order']))})
        self.assertEqual((result, '순서' in note), ('fail', True))
        (result, note), _ = self.run_case('E-CHAT-01', lambda job: {**good(job), 'order': good(job)['order'] + [good(job)['order'][0]]})
        self.assertEqual(result, 'fail')

    def test_a_rejected_send_fails_and_names_the_message(self):
        self.fake.handlers.clear()
        self.fake.on('POST', r'/chat/matches/[^/]+/messages', Reply(500, {'detail': 'down'}))
        (result, note), _ = self.run_case('E-CHAT-01', lambda job: said(loaded=True, seen={}, order=[], bubble_last=False))
        self.assertEqual(result, 'fail')
        self.assertIn('보내기', note)

    def test_a_room_that_never_finished_loading_is_blocked_and_nothing_is_sent(self):
        (result, note), _ = self.case('E-CHAT-01', lambda job: said(loaded=False, error=None))  # 실제 앱은 이때 step 을 안 부른다 — midway 없는 가짜 앱
        self.assertEqual(result, 'blocked', note)
        self.assertEqual(self.fake.by('POST', '/chat/matches/'), [])

    def test_the_db_must_hold_exactly_the_twenty_rows(self):
        def twice(sent):
            for _ in range(2):
                self.put('messages', match_id=sent['path'].split('/')[3], sender_id=self.who(sent), kind='text',
                         body=sent['body']['body'], created_at=now().isoformat())
            return Reply(201, {})
        self.fake.handlers.clear()
        self.fake.on('POST', r'/chat/matches/[^/]+/messages', twice)
        (result, note), _ = self.run_case('E-CHAT-01', self.good())
        self.assertEqual(result, 'fail')
        self.assertIn('DB', note)


# ── E-CHAT-07 ────────────────────────────────────────────────────────────────────────────────────────

class UnreadTest(Phone9):
    def good(self, **override):
        return lambda job: said(**{'before': {'row': '3', 'nav': '3'}, 'after': {'row': None, 'nav': None}, 'pulled': 'drag', **override})

    def test_07_three_messages_while_the_list_is_open_then_badges_three_and_after_the_room_zero(self):
        (result, note), app = self.run_case('E-CHAT-07', self.good())
        self.assertEqual((result, note), ('pass', '당기기: 손가락 끌기'))
        self.assertEqual(app.jobs, [{'token_hash': 'h', 'nickname': self.nick(1)}])  # 폰 계정은 B(큰 id), 상대 A 는 id-1
        self.assertEqual(self.events, ['step', 'go'])
        sends = self.fake.by('POST', '/chat/matches/')
        self.assertEqual([s['auth'] for s in sends], ['tok-1'] * 3)
        self.assertEqual(len({s['body']['body'] for s in sends}), 3)
        self.assert_all_home()

    def test_07_fails_on_wrong_badges_before_or_after_or_a_missing_word(self):
        for override in ({'before': {'row': '2', 'nav': '3'}}, {'before': {'row': '3', 'nav': None}}, {'before': {'row': None, 'nav': None}},
                         {'after': {'row': '3', 'nav': None}}, {'after': {'row': None, 'nav': '3'}}, {'before': {'row': '3'}}):
            (result, _), _ = self.run_case('E-CHAT-07', self.good(**override))
            self.assertEqual(result, 'fail', override)
        (result, _), _ = self.run_case('E-CHAT-07', lambda job: said())
        self.assertEqual(result, 'fail')

    def test_07_a_refresh_by_show_is_noted_as_a_pull_that_did_not_move_the_list(self):
        (result, note), _ = self.run_case('E-CHAT-07', self.good(pulled='show'))
        self.assertEqual(result, 'pass', note)
        self.assertIn('show()', note)
        self.assertIn('손가락', note)

    def test_07_a_failed_send_is_a_fail_before_judging_the_screen(self):
        self.fake.handlers.clear()
        self.fake.on('POST', r'/chat/matches/[^/]+/messages', Reply(500, {'detail': 'down'}))
        (result, note), _ = self.run_case('E-CHAT-07', self.good())
        self.assertEqual(result, 'fail')
        self.assertIn('A 보내기', note)


# ── 망을 끊는 가설(22 · 24 · 72) · 앱을 HOME 으로(23) ─────────────────────────────────────────────────

class DeviceBase(Phone9):
    """가짜 adb 와 가짜 보내기 · API 가 일어난 순서를 [events] 에 남긴다."""

    def setUp(self):
        super().setUp()
        self.state = {'airplane': 'disabled'}

        def fake_adb(serial, *args, check=True):
            if args[-2:-1] == ('airplane-mode',) and args[-1] in ('enable', 'disable'):
                self.state['airplane'] = args[-1] + 'd'
                self.events.append(args[-1])
            elif args[-1] == 'KEYCODE_HOME':
                self.events.append('home')
            elif 'monkey' in args:
                self.events.append('front')
            return self.state['airplane'] + '\n' if args[-1] == 'airplane-mode' else ''

        real_send, real_api = area3_chat_rt._send, area3_chat_rt._api

        def logged_send(run, account, match_id, body, **options):
            self.events.append('send')
            return real_send(run, account, match_id, body, **options)

        def logged_api(run, method, path, token, body=None, **options):
            self.events.append(f"api:{path.rsplit('/', 1)[-1]}")
            return real_api(run, method, path, token, body, **options)

        for patcher in (mock.patch.object(tools, 'adb', fake_adb), mock.patch.object(Run, 'shot'),
                        mock.patch.object(area3_chat_rt, '_send', logged_send), mock.patch.object(area3_chat_rt, '_api', logged_api)):
            patcher.start()
            self.addCleanup(patcher.stop)

    def slept(self):
        import time
        return [call.args[0] for call in time.sleep.call_args_list if call.args]

    def seen_now(self, bodies, delay=0.5):
        """앱이 방 뷰모델에서 [bodies] 를 서버가 찍은 시각 + [delay]초에 처음 봤다."""
        made = self.created()
        return {b: stamp(made[b] + timedelta(seconds=delay)) for b in bodies if b in made}

    def stepping(self, name, steps, answer):
        return self.case(name, answer, StepsApp(as_fn(answer), steps, self.events))


class ReconnectTest(DeviceBase):
    def good(self, **override):
        def answer(job):
            made = self.created()
            order = sorted(made, key=made.get)
            return said(**{'loaded': True, 'banner': True, 'banner_seconds': 12.5, 'retried': True, 'seen': self.seen_now(job['bodies']),
                           'order': order, 'bubble_last': True, **override})
        return answer

    def test_22_cut_then_five_while_offline_then_restore_then_retry_shows_all_five_in_order(self):
        (result, note), app = self.stepping('E-CHAT-22', ['cut', 'offline'], self.good())
        self.assertEqual(result, 'pass', note)
        self.assertEqual(self.events, ['step', 'enable', 'go', 'step'] + ['send'] * 5 + ['disable', 'go'])
        job = app.jobs[0]
        self.assertEqual(set(job), {'token_hash', 'nickname', 'bodies'})
        self.assertEqual(len(job['bodies']), 5)
        self.assertEqual([s['body']['body'] for s in self.fake.by('POST', '/chat/matches/')], job['bodies'])
        self.assertEqual(self.state['airplane'], 'disabled')
        self.assertIn('다시 시도', note)
        self.assert_all_home()

    def test_22_a_banner_that_vanished_before_the_press_says_so_in_the_memo(self):
        (result, note), _ = self.stepping('E-CHAT-22', ['cut', 'offline'], self.good(retried=False))
        self.assertEqual(result, 'pass', note)
        self.assertIn('눌러 보기 전에 자동으로 사라져', note)
        (result, note), _ = self.stepping('E-CHAT-22', ['cut', 'offline'], self.good(retried=True))
        self.assertEqual(result, 'pass', note)
        self.assertNotIn('눌러 보기 전에', note)

    def test_22_fails_without_the_banner_with_missing_or_misordered_or_doubled_lines(self):
        for override in ({'banner': False}, {'order': []}, {'seen': {}}, {'bubble_last': False}):
            (result, note), _ = self.stepping('E-CHAT-22', ['cut', 'offline'], self.good(**override))
            self.assertEqual(result, 'fail', override)
        (result, note), _ = self.stepping('E-CHAT-22', ['cut', 'offline'], lambda job: {**self.good()(job), 'order': job['bodies'][::-1]})
        self.assertEqual((result, '순서' in note), ('fail', True))
        (result, note), _ = self.stepping('E-CHAT-22', ['cut', 'offline'], lambda job: {**self.good()(job), 'order': job['bodies'] + job['bodies'][:1]})
        self.assertEqual(result, 'fail')

    def test_22_the_network_comes_back_even_when_the_app_dies_after_the_cut(self):
        class Dies(StepsApp):
            def __call__(self, midway=None, **job):
                midway({'step': 'cut'})
                raise RuntimeError('끊은 채로 죽음')
        with self.assertRaises(RuntimeError):
            self.case('E-CHAT-22', self.good(), Dies(self.good(), ['cut', 'offline'], self.events))
        self.assertEqual(self.state['airplane'], 'disabled')

    def test_72_a_five_second_cut_with_three_missed_and_the_banner_or_the_lines_back_within_ten_seconds(self):
        for name, extra in (('banner', {'banner': True, 'shown': 0}), ('refilled', {'banner': False, 'shown': 3}), ('both', {'banner': True, 'shown': 3})):
            self.events.clear()
            (result, note), app = self.stepping('E-CHAT-72', ['cut'], lambda job, extra=extra: said(
                **{'loaded': True, 'seconds': 2.0, 'order': job['bodies'] if extra['shown'] == 3 else [], **extra}))
            self.assertEqual(result, 'pass', f'{name}: {note}')
            self.assertEqual(self.events, ['step', 'enable'] + ['send'] * 3 + ['disable', 'go'], name)  # 끊기 → 3건 → 켜기
            self.assertEqual(app.jobs[0]['bodies'], [s['body']['body'] for s in self.fake.by('POST', '/chat/matches/')][-3:])
        self.assertEqual(area3_chat_rt.CUT_SECONDS, 5)

    def test_72_waits_out_the_five_seconds_and_restores_without_the_eight_second_settle(self):
        self.stepping('E-CHAT-72', ['cut'], said(loaded=True, banner=True, shown=0, seconds=1.0, order=[]))
        waits = self.slept()
        self.assertTrue(any(4.0 < w <= 5.0 for w in waits), waits)  # 끊은 지 5초가 되도록 남은 만큼
        self.assertNotIn(notify.SETTLE_SECONDS, waits)  # 켠 직후부터 10초를 센다

    def test_72_fails_when_neither_the_banner_nor_the_lines_come_back_or_the_order_is_wrong(self):
        (result, note), _ = self.stepping('E-CHAT-72', ['cut'], said(loaded=True, banner=False, shown=0, seconds=10.0, order=[]))
        self.assertEqual(result, 'fail')
        self.assertIn('확인 필요', note)  # 시나리오: 다시 붙으면 앱이 다시 읽지 않는 구조일 수 있다
        (result, note), _ = self.stepping('E-CHAT-72', ['cut'], lambda job: said(loaded=True, banner=False, shown=3, seconds=2.0, order=job['bodies'][::-1]))
        self.assertEqual((result, '순서' in note), ('fail', True))
        (result, _), _ = self.stepping('E-CHAT-72', ['cut'], lambda job: said(loaded=True, banner=False, shown=2, seconds=10.0, order=job['bodies'][:2]))
        self.assertEqual(result, 'fail')  # 3건 중 2건이면 "모두" 가 아니다

    def test_72_a_banner_that_came_and_went_without_the_lines_is_a_lost_message(self):
        """시나리오 72: 배너가 "뜨거나" 저절로 "채워져야" 한다. 배너가 켜졌다 꺼졌다는 것은 통로가 다시 붙어 다시 읽었다는 뜻인데 3건이 없으면 놓친 글이 사라진 것."""
        (result, note), _ = self.stepping('E-CHAT-72', ['cut'], said(loaded=True, banner=False, banner_was=True, shown=0, seconds=10.0, order=[]))
        self.assertEqual(result, 'fail')
        self.assertIn('켜졌다 꺼', note)
        (result, note), _ = self.stepping('E-CHAT-72', ['cut'], lambda job: said(loaded=True, banner=False, banner_was=True, shown=3, seconds=3.0, order=job['bodies']))
        self.assertEqual(result, 'pass', note)  # 켜졌다 꺼졌어도 3건이 채워졌으면 놓친 글은 안 사라졌다
        (result, note), _ = self.stepping('E-CHAT-72', ['cut'], said(loaded=True, banner=True, banner_was=True, shown=0, seconds=10.0, order=[]))
        self.assertEqual(result, 'pass', note)  # 아직 떠 있는 배너 = 사용자가 "다시 시도" 로 찾을 수 있다

    def test_72_the_network_is_restored_when_the_app_is_blocked(self):
        (result, _), _ = self.stepping('E-CHAT-72', ['cut'], lambda job: {'result': 'blocked', 'note': '못 찾음'})
        self.assertEqual(result, 'blocked')
        self.assertEqual(self.state['airplane'], 'disabled')

    def test_72_a_room_that_never_loaded_is_blocked_before_any_cut(self):
        (result, note), _ = self.case('E-CHAT-72', lambda job: said(loaded=False, error=None))
        self.assertEqual(result, 'blocked', note)
        self.assertNotIn('enable', self.events)


class ResumeTest(DeviceBase):
    def good(self, early=0, late=1.5, **override):
        def answer(job):
            made = self.created()
            bodies = job['bodies']
            resumed = max(made.values()) + timedelta(seconds=3)
            seen = {b: stamp(resumed - timedelta(seconds=1) if i < early else resumed + timedelta(seconds=late)) for i, b in enumerate(bodies)}
            return said(**{'loaded': True, 'seen': seen, 'order': sorted(made, key=made.get), 'bubble_last': True, 'paused': True,
                           'resumed_at': stamp(resumed), 'waited_ms': 1500, **override})
        return answer

    def test_23_home_then_three_then_front_and_all_three_show_without_a_tap(self):
        (result, note), app = self.run_case('E-CHAT-23', self.good())
        self.assertEqual(result, 'pass', note)
        self.assertEqual(self.events, ['step', 'home'] + ['send'] * 3 + ['front', 'go'])  # HOME → 3건 → 앱을 앞으로 → 앱이 이어 감
        self.assertEqual(set(app.jobs[0]), {'token_hash', 'nickname', 'bodies'})
        self.assertEqual(len(app.jobs[0]['bodies']), 3)
        self.assertIn('1.50초', note)
        self.assertIn('기록', note)
        self.assert_all_home()

    def test_23_lines_that_came_in_the_background_are_counted_apart(self):
        (result, note), _ = self.run_case('E-CHAT-23', self.good(early=2, late=0.4))
        self.assertEqual(result, 'pass', note)
        self.assertIn('배경에 있는 동안 이미 도착 2건', note)

    def test_23_waits_in_the_background_before_the_three_and_before_coming_back(self):
        self.run_case('E-CHAT-23', self.good())
        self.assertGreaterEqual(len([w for w in self.slept() if w >= 1]), 2)  # HOME 뒤 · 보낸 뒤 각각 쉰다

    def test_23_fails_on_a_missing_line_a_wrong_order_a_missing_bubble_or_a_late_return(self):
        for override in ({'seen': {}}, {'order': []}, {'bubble_last': False}, {'late': 12.0}):
            late = override.pop('late', 1.5)
            (result, note), _ = self.run_case('E-CHAT-23', self.good(late=late, **override))
            self.assertEqual(result, 'fail', override)
        (result, note), _ = self.run_case('E-CHAT-23', lambda job: {**self.good()(job), 'order': job['bodies'][::-1]})
        self.assertEqual((result, '순서' in note), ('fail', True))

    def test_23_an_app_that_went_to_the_background_but_never_saw_the_resume_still_judges_the_lines(self):
        (result, note), _ = self.run_case('E-CHAT-23', self.good(resumed_at=None, paused=True))
        self.assertEqual(result, 'pass', note)
        self.assertIn('돌아옴', note)  # 앱이 onResume 을 못 봄 — 걸린 시간은 앱이 잰 값으로

    def test_23_an_app_that_never_went_to_the_background_is_blocked_not_passed(self):
        """HOME 이 안 먹어 앱이 배경에 안 갔으면 "돌아온 뒤 저절로 붙는다" 를 본 것이 아니다."""
        for paused in (False, None):
            (result, note), _ = self.run_case('E-CHAT-23', self.good(resumed_at=None, paused=paused))
            self.assertEqual(result, 'blocked', note)
            self.assertIn('배경 진입 안 됨', note)
        (result, note), _ = self.run_case('E-CHAT-23', lambda job: {k: v for k, v in self.good()(job).items() if k != 'paused'})
        self.assertEqual(result, 'blocked', note)  # 앱이 paused 를 아예 안 말해도


class MissedTest(DeviceBase):
    KAKAO = 'e2ekakao'

    def setUp(self):
        super().setUp()
        self.fake.on('GET', r'/rest/v1/profile_private', lambda sent: Reply(200, [{'kakao_id': self.KAKAO}]))

    def good(self, **override):
        def answer(job):
            if job['variant'] == 'left':
                shown = {'input': False, 'notice': True, 'card': False, 'kakao': False}
            else:
                shown = {'input': True, 'notice': False, 'card': True, 'kakao': True}
            return said(**{'loaded': True, 'banner': True, 'retried': True, 'seconds': 1.2, **shown, **override})
        return answer

    def test_24_two_rooms_one_where_a_leaves_and_one_where_both_accept_while_offline(self):
        (result, note), app = self.stepping('E-CHAT-24', ['cut', 'changed'], self.good())
        self.assertEqual(result, 'pass', note)
        self.assertEqual([j['variant'] for j in app.jobs], ['left', 'passed'])
        self.assertNotIn('kakao', app.jobs[0])
        self.assertEqual(app.jobs[1]['kakao'], self.KAKAO)
        head = ['step', 'enable', 'go', 'step']
        want = head + ['api:leave', 'disable', 'go'] + head + ['api:trust', 'api:trust', 'disable', 'go']
        self.assertEqual(self.events, want)  # 끊기 → 바뀜(나가기 / 두 수락) → 켜기, 판마다
        self.assertEqual(self.state['airplane'], 'disabled')
        posts = self.fake.by('POST', '/chat/matches/')
        self.assertEqual([s['auth'] for s in posts if s['path'].endswith('/leave')], ['tok-1'])  # 상대 A 가 나간다
        self.assertEqual(sorted(s['auth'] for s in posts if s['path'].endswith('/trust')), ['tok-3', 'tok-4'])  # 둘 다 수락 — 폰 계정(B) 토큰도 PC 가
        self.assert_all_home()

    def test_24_fails_when_the_input_stays_or_the_card_or_the_kakao_id_is_missing(self):
        for override in ({'input': True}, {'notice': False}):
            (result, note), _ = self.stepping('E-CHAT-24', ['cut', 'changed'], self.good(**override))
            self.assertEqual(result, 'fail', override)
            self.assertIn('left', note)
        for override in ({'card': False}, {'kakao': False}, {'input': False}):
            (result, note), _ = self.stepping('E-CHAT-24', ['cut', 'changed'], self.good(**override))
            self.assertEqual(result, 'fail', override)
            self.assertIn('passed', note)

    def test_24_no_banner_is_noted_but_the_screen_after_reconnect_decides(self):
        (result, note), _ = self.stepping('E-CHAT-24', ['cut', 'changed'], self.good(banner=False, retried=False))
        self.assertEqual(result, 'pass', note)
        self.assertIn('배너', note)

    def test_24_a_banner_that_vanished_before_the_press_is_told_apart_from_no_banner(self):
        """실기기: 배너를 확인하고 누르는 사이 통로가 스스로 다시 붙어 배너가 내려간다 — "배너가 안 떴다" 로만 읽히면 안 된다."""
        (result, note), _ = self.stepping('E-CHAT-24', ['cut', 'changed'], self.good(banner=True, retried=False))
        self.assertEqual(result, 'pass', note)
        self.assertIn('눌러 보기 전에 자동으로 사라져', note)
        self.assertNotIn('끊긴 동안 배너가 안 떠', note)
        (result, note), _ = self.stepping('E-CHAT-24', ['cut', 'changed'], self.good(banner=False, retried=False))
        self.assertIn('끊긴 동안 배너가 안 떠', note)
        self.assertNotIn('눌러 보기 전에', note)

    def test_24_a_pressed_retry_leaves_no_note(self):
        (result, note), _ = self.stepping('E-CHAT-24', ['cut', 'changed'], self.good(banner=True, retried=True))
        self.assertEqual((result, note), ('pass', ''))

    def test_24_the_screen_still_decides_when_the_banner_vanished(self):
        (result, note), _ = self.stepping('E-CHAT-24', ['cut', 'changed'], self.good(banner=True, retried=False, input=True))
        self.assertEqual(result, 'fail', note)

    def test_24_a_partner_without_a_kakao_id_is_blocked(self):
        self.fake.handlers[:] = [h for h in self.fake.handlers if 'profile_private' not in h[1].pattern]
        self.fake.on('GET', r'/rest/v1/profile_private', Reply(200, [{'kakao_id': None}]))
        (result, note), app = self.stepping('E-CHAT-24', ['cut', 'changed'], self.good())
        self.assertEqual(result, 'blocked', note)
        self.assertIn('kakao_id', note)
        self.assertEqual(app.jobs, [])  # 첫 판 앱을 켜기 전에 막힌다 — 두 판 계정을 먼저 만들고 아이디를 본다
        self.assertNotIn('enable', self.events)

    def test_24_a_failed_leave_is_a_fail(self):
        self.fake.handlers.insert(0, ('POST', re.compile(r'/chat/matches/[^/]+/leave'), Reply(500, {'detail': 'down'})))
        (result, note), _ = self.stepping('E-CHAT-24', ['cut', 'changed'], self.good())
        self.assertEqual(result, 'fail')
        self.assertIn('A 나가기', note)


# ── E-CHAT-61 ────────────────────────────────────────────────────────────────────────────────────────

class LeftOpenTest(Phone9):
    def good(self, **override):
        return lambda job: said(**{'loaded': True, 'line': True, 'switched_ms': 600, 'input': False, 'notice': True, 'send_error': None, **override})

    def test_61_a_leaves_while_b_has_the_room_open_and_the_input_becomes_the_notice_within_two_seconds(self):
        (result, note), app = self.run_case('E-CHAT-61', self.good())
        self.assertEqual(result, 'pass', note)
        job = app.jobs[0]
        self.assertEqual(job, {'token_hash': 'h', 'nickname': self.nick(1), 'line': f'{self.nick(1)}님이 채팅방을 나갔어요', 'text': 'E2E-61'})
        self.assertEqual(self.events, ['step', 'go'])
        leaves = [s for s in self.fake.by('POST', '/chat/matches/') if s['path'].endswith('/leave')]
        self.assertEqual([s['auth'] for s in leaves], ['tok-1'])  # A 가 한 번 나간다
        self.assertIsNotNone(self.rows('match_participants', profile_id='id-1')[0].get('left_at'))
        self.assert_all_home()

    def test_61_fails_when_the_input_stays_and_names_the_error_the_send_attempt_got(self):
        (result, note), _ = self.run_case('E-CHAT-61', self.good(switched_ms=None, input=True, notice=False, send_error='상대가 대화를 나갔어요'))
        self.assertEqual(result, 'fail')
        self.assertIn('상대가 대화를 나갔어요', note)
        self.assertIn('입력창', note)

    def test_61_fails_when_it_takes_over_two_seconds_or_both_input_and_notice_show(self):
        (result, note), _ = self.run_case('E-CHAT-61', self.good(switched_ms=2600))
        self.assertEqual((result, '2.6' in note), ('fail', True))
        (result, _), _ = self.run_case('E-CHAT-61', self.good(switched_ms=500, input=True))
        self.assertEqual(result, 'fail')
        (result, _), _ = self.run_case('E-CHAT-61', self.good(switched_ms=500, notice=False))
        self.assertEqual(result, 'fail')

    def test_61_exactly_two_seconds_is_in_time(self):
        (result, note), _ = self.run_case('E-CHAT-61', self.good(switched_ms=2000))
        self.assertEqual(result, 'pass', note)

    def test_61_fails_when_the_leave_line_never_shows(self):
        (result, note), _ = self.run_case('E-CHAT-61', said(loaded=True, line=False))
        self.assertEqual(result, 'fail')
        self.assertIn('나감 줄', note)

    def test_61_fails_when_the_left_room_stored_a_text_from_the_phone_account(self):
        def stored(job):
            self.text_sent('E2E-61', sender='id-2')
            return self.good(switched_ms=None, input=True, notice=False, send_error=None)(job)
        (result, note), _ = self.run_case('E-CHAT-61', stored)
        self.assertEqual(result, 'fail')
        self.assertIn('저장', note)

    def test_61_a_room_that_never_loaded_is_blocked_and_nobody_leaves(self):
        (result, note), _ = self.case('E-CHAT-61', lambda job: said(loaded=False, error=None))
        self.assertEqual(result, 'blocked', note)
        self.assertEqual([s for s in self.fake.by('POST', '/chat/matches/') if s['path'].endswith('/leave')], [])


# ── 두 기기(E-CHAT-03 · 58) ───────────────────────────────────────────────────────────────────────────

class Script:
    """twodev.bound 가 주는 `two` 대신 — 앱이 말하는 차례(script = [(쪽, step 이름, 앱 말(또는 그것을 돌려주는 함수), 그 step 에 닿기 전에 서버에 남기는 일)])대로
    plan 의 핸들러를 부른다. plan 의 열쇠와 script 가 한 치도 다르면 시험이 깨진다. [preset] 은 상대 앱이 이미 세워 둔 Sync 이름 — 핸들러를 한 줄로 부르므로
    "서로 기다린다" 는 [SyncTest] 가 진짜 스레드로 따로 본다."""

    def __init__(self, test, script, result=('pass', 'A: pass  B: pass'), preset=(), partial=False):
        self.test, self.script, self.result, self.preset, self.partial = test, script, result, preset, partial
        self.went, self.limit, self.a_job, self.b_job = [], None, None, None

    def __call__(self, plan, a_job=None, b_job=None, **limit):
        self.a_job, self.b_job, self.limit = a_job, b_job, limit
        keys = sorted((side, step) for side, step, _, _ in self.script)
        if self.partial:  # 앱이 중간에 막혀 뒤 step 에 못 닿은 모습 — 닿은 step 은 plan 에 있어야 한다
            self.test.assertTrue(set(keys) <= set(plan), keys)
        else:
            self.test.assertEqual(sorted(plan), keys)
        sync = twodev.Sync()
        for name in self.preset:
            sync.set(name)
        for side, step, payload, effect in self.script:
            if effect:
                effect()
            said = {'step': step, 't': 0, **(payload() if callable(payload) else payload)}
            self.went.append((side, step, plan[(side, step)](said, sync)))
        return self.result


class TwoBase(Phone9):
    A, B = 'id-1', 'id-2'  # 폰(A) = 작은 id, 에뮬(B) = 큰 id

    def setUp(self):
        super().setUp()
        for patcher in (mock.patch.object(area3_chat_rt, 'PEER', 0.05),):
            patcher.start()
            self.addCleanup(patcher.stop)

    def go(self, case, script, result=('pass', 'A: pass  B: pass'), partial=False):
        self.fake.tables.clear()
        self.fake.sent.clear()
        self.fake.statuses.clear()
        self.fake.users.clear()
        self.fake.verifies = self.fake._ids = 0
        self.two = Script(self, script, result, preset=('a-ready', 'b-ready', 'a-sent', 'b-sent'), partial=partial)
        return twodev.TWO[case](self.run_, self.two)

    def line(self, who, body, at, kind='text', ident=None):
        self.put('messages', id=ident or f'm-{body}', match_id=self.match(), sender_id=who, kind=kind, body=body, created_at=at.isoformat())


class AlternateTest(TwoBase):
    START = now().replace(microsecond=0)

    def bodies(self):
        job = self.two.a_job
        return job['mine'], job['theirs']

    def alternate(self, swap=None, drop=None, twice=None, a_delay=0.6, b_delay=0.6, slow=None, ignore_id=False, negative=0, busy=None, miss=None, done=None):
        """앱 둘이 서로 번갈아 20건씩 보낸 일 — [effect] 가 DB 에 40줄을 0.5초 칸으로 넣고, 두 앱이 화면 순서 · 처음 본 시각을 말한다."""
        def effect():
            mine, theirs = self.bodies()
            for i in range(20):
                self.line(self.A, mine[i], self.START + timedelta(seconds=i))
                self.line(self.B, theirs[i], self.START + timedelta(seconds=i + 0.5))

        def says(who, other_delay):
            def payload():
                made, ids = self.created(), {m['body']: m['id'] for m in self.rows('messages')}
                order = sorted(made, key=(lambda body: (made[body], body)) if ignore_id else (lambda body: (made[body], ids[body])))
                if swap:
                    order[swap[0]], order[swap[1]] = order[swap[1]], order[swap[0]]
                if drop is not None:
                    order.pop(drop)
                if twice is not None:
                    order.insert(twice + 1, order[twice])
                mine, theirs = self.bodies()
                others = theirs if who == 'A' else mine
                seen = {b: stamp(made[b] + timedelta(seconds=other_delay)) for b in others if b in made}  # DB 가 잃은 줄은 앱도 못 봤다
                if negative and who == 'B':  # B 폰 시계가 느려 앞의 [negative]줄이 서버 시각보다 앞선다
                    for body in others[:negative]:
                        seen[body] = stamp(made[body] - timedelta(seconds=1.5))
                if slow and who == slow[0]:
                    seen[others[slow[1]]] = stamp(made[others[slow[1]]] + timedelta(seconds=slow[2]))
                if miss and who == miss[0]:  # 상대의 맨 끝 줄을 못 받았다(구독이 안 줬거나 시험이 일찍 끝났다)
                    for index in miss[1]:
                        seen.pop(others[index], None)
                        order.remove(others[index])
                said = {'order': order, 'seen': seen}
                if done:  # 앱 시계로 "다 기다렸다" 고 말한 때
                    said['done_at'] = stamp(done(who, made))
                if busy:  # 받는 기기가 자기 글을 보내던 때(앱 시계) — 옛 앱은 이 키를 안 말한다
                    said['sent_at'] = busy(who, made)
                return said
            return payload

        return [('A', 'ready', {}, None), ('B', 'ready', {}, None), ('A', 'sent', {}, effect), ('B', 'sent', {}, None),
                ('A', 'done', says('A', a_delay), None), ('B', 'done', says('B', b_delay), None)]

    def test_03_both_screens_show_the_db_order_with_all_forty_lines_and_each_line_in_time(self):
        result, note = self.go('E-CHAT-03', self.alternate())
        self.assertEqual(result, 'pass', note)
        a, b = self.two.a_job, self.two.b_job
        self.assertEqual(set(a), {'token_hash', 'nickname', 'mine', 'theirs', 'offset', 'gap'})
        self.assertEqual((a['offset'], b['offset'], a['gap'], b['gap']), (0.0, 0.5, 1.0, 1.0))  # B 가 0.5초 늦게 → 0.5초 간격으로 엇갈린다
        self.assertEqual((a['nickname'], b['nickname']), (self.nick(2), self.nick(1)))
        self.assertEqual((a['mine'], a['theirs']), (b['theirs'], b['mine']))
        self.assertEqual((len(a['mine']), len(a['theirs']), len(set(a['mine'] + a['theirs']))), (20, 20, 40))
        self.assertTrue(all(re.fullmatch(r'E2E-03-A\d\d-[0-9a-f]+', x) for x in a['mine']))
        self.assertTrue(all(re.fullmatch(r'E2E-03-B\d\d-[0-9a-f]+', x) for x in a['theirs']))
        self.assertEqual(self.two.limit, area3_chat_rt.LIMITS)
        self.assertIn('A 화면', note)
        self.assertIn('B 화면', note)
        self.assert_pair(self.match(), self.A, self.B)
        self.assert_all_home()

    def tied(self, **kwargs):
        """첫 두 줄(A 의 1번 · B 의 1번)이 같은 시각 — id 는 본문 순서와 거꾸로(B 의 줄이 먼저)."""
        script = self.alternate(**kwargs)
        real = script[2][3]

        def effect():
            real()
            first, second = self.rows('messages')[:2]
            second['created_at'] = first['created_at']
            first['id'], second['id'] = 'b-later', 'a-earlier'
        script[2] = (*script[2][:3], effect)
        return script

    def test_03_lines_with_the_same_time_are_ordered_by_id(self):
        """DB 순서는 (created_at, id) — 같은 시각이면 id 순."""
        result, note = self.go('E-CHAT-03', self.tied())
        self.assertEqual(result, 'pass', note)

    def test_03_a_screen_that_ignores_the_id_on_a_tie_fails(self):
        result, note = self.go('E-CHAT-03', self.tied(ignore_id=True))
        self.assertEqual(result, 'fail', note)
        self.assertIn('순서', note)

    def test_03_fails_on_a_different_order_a_missing_or_doubled_line(self):
        for label, kwargs in (('순서', {'swap': (3, 4)}), ('줄', {'drop': 10}), ('겹', {'twice': 7})):
            result, note = self.go('E-CHAT-03', self.alternate(**kwargs))
            self.assertEqual(result, 'fail', label)
            self.assertIn(label, note)

    def test_03_fails_when_a_line_takes_over_two_seconds_on_the_other_screen_and_names_it(self):
        result, note = self.go('E-CHAT-03', self.alternate(slow=('B', 5, 2.6)))
        self.assertEqual(result, 'fail')
        self.assertIn('B 화면', note)
        self.assertIn('6번 글이 2.6초', note)
        result, note = self.go('E-CHAT-03', self.alternate(a_delay=2.0, b_delay=2.0))
        self.assertEqual(result, 'pass', note)  # 정확히 2.0초는 안

    def test_03_negative_delays_are_left_out_of_the_judgement_and_counted(self):
        result, note = self.go('E-CHAT-03', self.alternate(negative=5))
        self.assertEqual(result, 'pass', note)
        self.assertIn('음수 5건', note)
        self.assertIn('시계 차', note)

    def test_03_a_screen_whose_clock_leaves_under_half_judgeable_blocks(self):
        result, note = self.go('E-CHAT-03', self.alternate(b_delay=-1.5))
        self.assertEqual(result, 'blocked', note)
        self.assertIn('시계 차로 판정 불가', note)

    def test_03_fails_when_the_db_lost_a_line_even_if_both_screens_agree(self):
        script = self.alternate()
        real = script[2][3]

        def lose():
            real()
            self.fake.tables['messages'].pop(7)
        script[2] = (*script[2][:3], lose)
        result, note = self.go('E-CHAT-03', script)
        self.assertEqual(result, 'fail')
        self.assertIn('DB 글 39행', note)

    def test_03_an_app_that_blocked_keeps_the_result_blocked_unless_the_pc_found_a_fail(self):
        result, note = self.go('E-CHAT-03', self.alternate(), result=('blocked', 'A: pass  B: blocked - 방이 안 읽힘'))
        self.assertEqual(result, 'blocked', note)
        result, note = self.go('E-CHAT-03', self.alternate(swap=(1, 2)), result=('blocked', 'A: pass  B: blocked'))
        self.assertEqual(result, 'fail', note)  # PC 가 직접 본 어긋남은 앱이 막혔어도 확정된 fail

    def test_03_an_app_that_blocked_before_writing_anything_leaves_the_result_blocked_not_a_db_fail(self):
        """앱이 방을 못 열어 막히면 DB 에는 아무것도 없다 — "DB 글 0행(기대 40)" 이 허위 fail 이 되면 진행 프로그램이 한 번 더 돈다."""
        script = [('A', 'ready', {}, None), ('B', 'ready', {}, None)]
        result, note = self.go('E-CHAT-03', script, result=('blocked', 'A: pass  B: blocked - 방이 안 읽힘'), partial=True)
        self.assertEqual(result, 'blocked', note)
        self.assertEqual(self.rows('messages'), [])

    def test_03_a_blocked_app_with_lines_already_in_the_db_still_gets_the_db_checks(self):
        alt = self.alternate(swap=(1, 2))
        result, note = self.go('E-CHAT-03', [('A', 'ready', {}, None), ('B', 'ready', {}, None), alt[2], alt[4]],
                               result=('blocked', 'A: pass  B: blocked'), partial=True)
        self.assertEqual(result, 'fail', note)

    def test_03_a_slow_line_says_whether_the_receiving_device_was_sending_just_before(self):
        """원인 가설(받는 기기의 자기 보내기 부하)을 증거로 가른다 — 판정(2.0초)은 그대로, 문구만 덧붙는다."""
        def near(who, made):  # B 가 6번 글을 본 시각(= 만든 시각 + 2.6초) 0.8초 앞에 자기 글을 보냈다
            others = self.two.a_job['mine'] if who == 'B' else self.two.b_job['mine']
            return [stamp(made[others[5]] + timedelta(seconds=2.6 - 0.8))]
        result, note = self.go('E-CHAT-03', self.alternate(slow=('B', 5, 2.6), busy=near))
        self.assertEqual(result, 'fail', note)
        self.assertIn('6번 글이 2.6초', note)
        self.assertIn('그 글이 보이기 직전 0.8초 안에 받는 기기도 자기 글을 보냄', note)

    def test_03_a_slow_line_with_the_receiver_quiet_says_so(self):
        def far(who, made):
            others = self.two.a_job['mine'] if who == 'B' else self.two.b_job['mine']
            return [stamp(made[others[5]] + timedelta(seconds=2.6 - 5.0))]  # 5초 전 — 3초 창 밖
        result, note = self.go('E-CHAT-03', self.alternate(slow=('B', 5, 2.6), busy=far))
        self.assertEqual(result, 'fail', note)
        self.assertIn('6번 글이 2.6초', note)
        self.assertIn('직전 3초 안에 받는 기기의 보내기는 없었음', note)
        self.assertNotIn('도 자기 글을 보냄', note)

    def test_03_without_sent_at_the_fail_text_is_the_old_one(self):
        """옛 앱 · 옛 가짜 앱은 sent_at 을 안 말한다 — 문구는 덧붙지 않고 판정도 그대로."""
        result, note = self.go('E-CHAT-03', self.alternate(slow=('B', 5, 2.6)))
        self.assertEqual(result, 'fail', note)
        self.assertNotIn('받는 기기', note)
        result, note = self.go('E-CHAT-03', self.alternate(slow=('B', 5, 2.6), busy=lambda who, made: []))
        self.assertEqual(result, 'fail', note)
        self.assertNotIn('받는 기기', note)  # 빈 목록 = 말한 게 없다

    def test_03_the_verdict_stays_at_two_seconds_with_or_without_sent_at(self):
        def near(who, made):
            others = self.two.a_job['mine'] if who == 'B' else self.two.b_job['mine']
            return [stamp(made[others[i]]) for i in range(20)]
        result, note = self.go('E-CHAT-03', self.alternate(a_delay=2.0, b_delay=2.0, busy=near))
        self.assertEqual(result, 'pass', note)  # 정확히 2.0초는 안 — 문구는 fail 에만 붙는다
        self.assertNotIn('받는 기기', note)
        result, note = self.go('E-CHAT-03', self.alternate(b_delay=2.1, busy=near))
        self.assertEqual(result, 'fail', note)

    def test_03_each_screen_gets_its_own_sent_at(self):
        """A 화면(상대 줄 = B 의 글)에는 A 가 말한 sent_at, B 화면에는 B 가 말한 것."""
        def own(who, made):
            return [f'{who}-marker']  # 읽을 수 없는 값 — 문구엔 안 쓰이고 앞 시험이 시각 쪽을 본다
        seen_by = {}
        import e2e.area3_chat_rt as module
        real = module._delays

        def spy(check, run, match_id, bodies, seen, label, kind='text', busy=None):
            seen_by[label] = busy
            return real(check, run, match_id, bodies, seen, label, kind, busy)
        with mock.patch.object(module, '_delays', spy):
            self.go('E-CHAT-03', self.alternate(busy=own))
        self.assertEqual(seen_by, {'A 화면': ['A-marker'], 'B 화면': ['B-marker']})

    def test_03_each_side_waits_for_the_other_to_have_sent_everything_before_it_is_let_go(self):
        """끝 맞춤 — 한쪽이 느리게 보내도 이쪽의 "40줄 기다림 20초" 는 상대가 다 보낸 뒤부터 센다. 한쪽이 안 오면 blocked."""
        import threading
        captured = {}

        class Grab:
            def __call__(inner, handlers, a_job=None, b_job=None, **limit):
                captured.update(handlers)
                return ('pass', '')
        self.fake.tables.clear()
        self.fake.users.clear()
        self.fake.verifies = self.fake._ids = 0
        twodev.TWO['E-CHAT-03'](self.run_, Grab())
        self.assertIn(('A', 'sent'), captured)
        self.assertIn(('B', 'sent'), captured)
        sync, order = twodev.Sync(), []

        def run(side):
            captured[(side, 'sent')]({'step': 'sent'}, sync)
            order.append(side)

        first = threading.Thread(target=run, args=('B',))
        with mock.patch.object(area3_chat_rt, 'PEER', 5):
            first.start()
            first.join(0.3)
            self.assertTrue(first.is_alive())  # A 가 아직 다 안 보냈으니 B 는 풀리지 않는다
            run('A')
            first.join(2)
        self.assertEqual(sorted(order), ['A', 'B'])
        self.assertFalse(first.is_alive())

    def test_03_a_side_whose_partner_never_finishes_sending_is_blocked(self):
        captured = {}

        class Grab:
            def __call__(inner, handlers, a_job=None, b_job=None, **limit):
                captured.update(handlers)
                return ('pass', '')
        self.fake.tables.clear()
        self.fake.users.clear()
        self.fake.verifies = self.fake._ids = 0
        twodev.TWO['E-CHAT-03'](self.run_, Grab())
        with self.assertRaises(tools.Blocked) as caught:
            captured[('A', 'sent')]({'step': 'sent'}, twodev.Sync())
        self.assertIn('B', str(caught.exception))

    def test_03_the_timeouts_hold_a_slow_emulator_and_the_wait_for_the_other_to_finish(self):
        slow_send = area3_chat_rt.SLOW_LINE * area3_chat_rt.ALT  # B 가 줄당 최대 3초 → 20줄 60초
        self.assertEqual(slow_send, 60)
        self.assertGreaterEqual(PEER_SECONDS, slow_send)  # "상대가 다 보낼 때까지" 의 상한이 느린 보내기를 담는다
        worst = area3_chat_rt.APP_OPEN + 5 + 2 + 60 + slow_send + slow_send + area3_chat_rt.CATCH_UP + 30  # 열기 · 데우기 · ready 어긋남 60 · 보내기 · sent 어긋남 · 기다림 · 여유
        self.assertGreaterEqual(area3_chat_rt.LIMITS['deadline'], worst)
        self.assertGreaterEqual(area3_chat_rt.LIMITS['side_timeout']['A'], slow_send + area3_chat_rt.CATCH_UP)
        self.assertEqual(tools.CASE_LIMITS['E-CHAT-03'], area3_chat_rt.LIMITS['deadline'] + 2 * 150)

    def test_03_a_line_the_screen_never_got_that_the_server_stored_before_the_end_blames_the_subscription(self):
        """"앱 38줄 · DB 40줄" — 맨 끝 두 줄이 서버에 먼저 저장됐는데 안 왔으면 구독이 안 준 것(앱/구독 의심)."""
        def sent_at(who, made):
            lines = self.two.b_job['mine'] if who == 'B' else self.two.a_job['mine']
            return [stamp(made[b] - timedelta(seconds=0.1)) for b in lines]
        result, note = self.go('E-CHAT-03', self.alternate(miss=('A', [18, 19]), busy=sent_at, done=lambda who, made: max(made.values()) + timedelta(seconds=21)))
        self.assertEqual(result, 'fail', note)
        self.assertIn('A 화면: 19번 20번 글이 화면(뷰모델)에 안 뜸', note)
        self.assertIn('A 화면 19번 글(못 받음): 서버 저장 시각이 A 가 끝을 말하기', note)
        self.assertIn('전', note)
        self.assertIn('시계 차가 섞임', note)
        self.assertIn('구독이 안 줌(앱/구독 의심)', note)
        self.assertNotIn('시험이 끝을 일찍 말함', note)
        self.assertIn('상대 기기 보내기 누름', note)  # B 의 sent_at 중 그 글(19번째)의 것
        self.assertIn('20번 글(못 받음)', note)

    def test_03_a_line_stored_after_the_app_said_it_was_done_blames_the_test(self):
        def sent_at(who, made):
            lines = self.two.b_job['mine'] if who == 'B' else self.two.a_job['mine']
            return [stamp(made[b] - timedelta(seconds=0.1)) for b in lines]
        late = lambda who, made: min(made.values()) + timedelta(seconds=5)  # noqa: E731 — 마지막 줄들이 저장되기 한참 전에 A 가 끝을 말했다
        result, note = self.go('E-CHAT-03', self.alternate(miss=('A', [18, 19]), busy=sent_at, done=late))
        self.assertEqual(result, 'fail', note)
        self.assertIn('시험이 끝을 일찍 말함', note)
        self.assertIn('후', note)
        self.assertNotIn('구독이 안 줌', note)

    def test_03_without_done_at_or_sent_at_the_old_text_stays_and_says_why_no_story(self):
        result, note = self.go('E-CHAT-03', self.alternate(miss=('A', [19])))
        self.assertEqual(result, 'fail', note)
        self.assertIn('20번 글이 화면(뷰모델)에 안 뜸', note)
        self.assertIn('done_at 을 안 말함', note)
        self.assertNotIn('구독이 안 줌', note)

    def test_03_the_order_text_tells_missing_lines_from_a_reversed_order(self):
        result, note = self.go('E-CHAT-03', self.alternate(miss=('A', [18, 19])))
        self.assertIn('빠진 줄 2건 때문, 나머지 순서는 DB 와 같음', note)
        self.assertNotIn('순서가 뒤바뀜', note)
        result, note = self.go('E-CHAT-03', self.alternate(swap=(3, 4)))
        self.assertIn('순서가 뒤바뀜', note)
        self.assertNotIn('빠진 줄', note)
        result, note = self.go('E-CHAT-03', self.alternate(miss=('A', [19]), swap=(3, 4)))
        self.assertIn('순서가 뒤바뀜', note)  # 빠진 줄이 있어도 나머지 순서가 틀리면 뒤바뀐 것

    def test_03_a_failed_run_leaves_both_apps_end_values_in_the_bundle_folder(self):
        import json
        path = self.run_.out / 'E-CHAT-03-done.json'
        path.unlink(missing_ok=True)
        result, note = self.go('E-CHAT-03', self.alternate(miss=('A', [19])))
        self.assertEqual(result, 'fail')
        self.assertTrue(path.exists())
        kept = json.loads(path.read_text(encoding='utf-8'))
        self.assertEqual(sorted(kept), ['A', 'B'])
        self.assertEqual(len(kept['A']['order']), 39)
        self.assertEqual(len(kept['B']['order']), 40)
        self.assertIn('seen', kept['A'])
        self.assertIn('E-CHAT-03-done.json', note)

    def test_03_a_passing_run_leaves_no_file(self):
        path = self.run_.out / 'E-CHAT-03-done.json'
        path.unlink(missing_ok=True)
        result, note = self.go('E-CHAT-03', self.alternate())
        self.assertEqual(result, 'pass', note)
        self.assertFalse(path.exists())

    def test_03_an_unwritable_folder_does_not_hide_the_verdict(self):
        from pathlib import Path
        real = Path.write_text

        def guarded(path, *args, **kwargs):  # 번들 폴더의 진단 파일만 못 쓴다
            if path.name.endswith('-done.json'):
                raise OSError('read-only')
            return real(path, *args, **kwargs)
        with mock.patch.object(Path, 'write_text', guarded):
            result, note = self.go('E-CHAT-03', self.alternate(miss=('A', [19])))
        self.assertEqual(result, 'fail', note)
        self.assertIn('진단 파일 못 씀', note)

    def test_03_each_side_waits_for_the_other_to_be_ready_before_it_is_let_go(self):
        """진짜 스레드 둘 — 한쪽 핸들러는 상대가 ready 를 세울 때까지 돌아오지 않는다(둘이 같이 풀려야 엇갈림이 맞는다)."""
        import threading
        captured = {}

        class Grab:
            def __call__(inner, handlers, a_job=None, b_job=None, **limit):
                captured.update(handlers)
                return ('pass', '')
        self.fake.tables.clear()
        self.fake.users.clear()
        self.fake.verifies = self.fake._ids = 0
        twodev.TWO['E-CHAT-03'](self.run_, Grab())
        sync, order = twodev.Sync(), []

        def run(side):
            captured[(side, 'ready')]({'step': 'ready'}, sync)
            order.append(side)

        first = threading.Thread(target=run, args=('A',))
        with mock.patch.object(area3_chat_rt, 'PEER', 5):
            first.start()
            first.join(0.3)
            self.assertTrue(first.is_alive())  # B 가 아직 안 와서 A 는 풀리지 않는다
            run('B')
            first.join(2)
        self.assertEqual(sorted(order), ['A', 'B'])
        self.assertFalse(first.is_alive())


class LeaveTest(TwoBase):
    def leaving(self, line=None, left_at=True, row_gone=True, on_list=True, room_gone=True, delay=0.7, shown=True, extra_lines=0):
        line_of = lambda: line or f"{self.nick(1)}님이 채팅방을 나갔어요"  # noqa: E731

        def effect():
            at = now()
            self.put('messages', id='left-1', match_id=self.match(), sender_id=self.A, kind='left', body=line_of(), created_at=at.isoformat())
            for _ in range(extra_lines):
                self.put('messages', id='left-2', match_id=self.match(), sender_id=self.A, kind='left', body=line_of(), created_at=at.isoformat())
            for row in self.rows('match_participants', profile_id=self.A):
                row['left_at'] = at.isoformat() if left_at else None

        def b_says():
            made = datetime.fromisoformat(self.rows('messages', kind='left')[0]['created_at'])
            return {'seen_at': stamp(made + timedelta(seconds=delay)), 'shown': shown, 'input': False, 'notice': True}

        return [('A', 'ready', {}, None), ('B', 'ready', {}, None),
                ('A', 'left', {'room_gone': room_gone, 'on_list': on_list, 'row_gone': row_gone}, effect), ('B', 'seen', b_says, None)]

    def test_58_a_leaves_by_the_menu_and_b_sees_the_line_within_two_seconds(self):
        result, note = self.go('E-CHAT-58', self.leaving())
        self.assertEqual(result, 'pass', note)
        a, b = self.two.a_job, self.two.b_job
        self.assertEqual(set(a), {'token_hash', 'nickname'})
        self.assertEqual(set(b), {'token_hash', 'nickname', 'line'})
        self.assertEqual((a['nickname'], b['nickname']), (self.nick(2), self.nick(1)))
        self.assertEqual(b['line'], f'{self.nick(1)}님이 채팅방을 나갔어요')  # 나간 사람 A 의 닉네임
        self.assertEqual(self.two.limit, area3_chat_rt.LIMITS)
        self.assertIn('0.70초', note)
        reads = [s for s in self.fake.by('GET', '/chat/conversations')]
        self.assertEqual([s['auth'] for s in reads], ['tok-1'])  # A 토큰으로 목록을 읽어 방이 없는지 본다
        self.assert_pair(self.match(), self.A, self.B)
        self.assert_all_home()

    def test_58_an_app_that_blocked_before_anyone_left_leaves_the_result_blocked_not_a_db_fail(self):
        script = [('A', 'ready', {}, None), ('B', 'ready', {}, None)]
        result, note = self.go('E-CHAT-58', script, result=('blocked', 'A: blocked - 방이 안 읽힘  B: pass'), partial=True)
        self.assertEqual(result, 'blocked', note)

    def test_58_fails_when_the_line_is_late_wrong_or_not_shown(self):
        for label, kwargs in (('2.6', {'delay': 2.6}), ('나감 줄', {'shown': False}), ('문구', {'line': 'A님이 나갔어요'})):
            result, note = self.go('E-CHAT-58', self.leaving(**kwargs))
            self.assertEqual(result, 'fail', label)
            self.assertIn(label, note)

    def test_58_exactly_two_seconds_passes(self):
        result, note = self.go('E-CHAT-58', self.leaving(delay=2.0))
        self.assertEqual(result, 'pass', note)

    def test_58_a_negative_delay_is_a_clock_difference_and_cannot_be_judged(self):
        result, note = self.go('E-CHAT-58', self.leaving(delay=-4.0))
        self.assertEqual(result, 'blocked', note)
        self.assertIn('시계 차로 판정 불가', note)

    def test_58_fails_when_a_screen_stays_in_the_room_or_the_room_stays_in_the_list(self):
        for label, kwargs in (('방', {'room_gone': False}), ('목록', {'on_list': False}), ('방이 목록에 남음', {'row_gone': False})):
            result, note = self.go('E-CHAT-58', self.leaving(**kwargs))
            self.assertEqual(result, 'fail', label)
            self.assertIn(label, note)

    def test_58_fails_when_the_server_did_not_mark_a_as_left_or_wrote_the_line_twice(self):
        result, note = self.go('E-CHAT-58', self.leaving(left_at=False))
        self.assertEqual(result, 'fail')
        self.assertIn('left_at', note)
        result, note = self.go('E-CHAT-58', self.leaving(extra_lines=1))
        self.assertEqual(result, 'fail')
        self.assertIn('나감 줄 2', note)

    def test_58_a_room_that_is_still_in_as_server_list_fails_even_if_the_screen_says_gone(self):
        self.fake.handlers[:] = [h for h in self.fake.handlers if 'conversations' not in h[1].pattern]
        self.fake.on('GET', r'/chat/conversations', lambda sent: Reply(200, {'conversations': [{'match_id': self.match()}]}))
        result, note = self.go('E-CHAT-58', self.leaving())
        self.assertEqual(result, 'fail')
        self.assertIn('GET /chat/conversations', note)


# ── 등록 ─────────────────────────────────────────────────────────────────────────────────────────────

class RegistryTest(Phone9):
    def dart(self, name):
        return (tools.ROOT / 'frontend' / 'integration_test' / name).read_text(encoding='utf-8')

    def test_the_bundles_are_eight_phone_cases_and_two_two_device_cases(self):
        self.assertEqual(area3.BUNDLES['area3-chat-rt'], PHONE)
        self.assertEqual(list(area3_chat_rt.PHONE9), PHONE)
        self.assertEqual(area1.BUNDLES['area3-chat-rt-two'], TWO)
        self.assertEqual(sorted(twodev.TWO), sorted(set(twodev.TWO) | set(TWO)))
        self.assertLessEqual(set(PHONE), set(area1.PHONE))
        for case in TWO:
            self.assertIn(case, twodev.TWO)
            self.assertNotIn(case, area1.PHONE)  # 두 기기 가설은 폰 한 대 묶음에 안 섞인다
        mine = set(PHONE + TWO)
        for name, cases in {**area3.BUNDLES, **area1.BUNDLES}.items():
            if name not in ('area3-chat-rt', 'area3-chat-rt-two'):
                self.assertFalse(mine & set(cases), name)  # 다른 묶음과 안 겹친다

    def test_main_runs_the_phone_cases_through_the_phone_and_the_two_cases_through_twodev(self):
        from e2e import __main__ as main
        self.assertEqual(main.BUNDLES['area3-chat-rt'], PHONE)
        self.assertEqual(main.BUNDLES['area3-chat-rt-two'], TWO)
        self.assertFalse(set(PHONE + TWO) & set(main.API_CASES))  # API 가설은 이 묶음에 없다
        for case in TWO:
            self.assertIs(twodev.TWO[case], area3_chat_rt.TWO9[case])
            self.assertTrue(main.case_limit(case, case in area1.PHONE or case not in main.API_CASES))  # 기기를 만지는 가설이라 시간 상한이 걸린다

    def test_case_limits_cover_the_worst_case_prep_waits_and_cuts(self):
        limits = {name: tools.CASE_LIMITS[name] for name in PHONE + TWO}
        self.assertEqual(limits, {'E-CHAT-01': 487.0, 'E-CHAT-02': 487.0, 'E-CHAT-07': 480, 'E-CHAT-22': 558, 'E-CHAT-23': 471, 'E-CHAT-24': 1056,
                                  'E-CHAT-61': 446, 'E-CHAT-72': 465, 'E-CHAT-03': 900, 'E-CHAT-58': 900})
        for name, seconds in limits.items():
            self.assertGreater(seconds, tools.CASE_LIMIT, name)  # 기본 420 으로는 모자란다
        self.assertGreaterEqual(limits['E-CHAT-03'], area3_chat_rt.LIMITS['deadline'] + 2 * 150)  # 두 기기 — deadline 앞에 계정 둘 준비

    def test_the_two_device_limits_leave_room_for_the_waits(self):
        sides = area3_chat_rt.LIMITS['side_timeout']
        self.assertGreater(sides['A'], area3_chat_rt.PEER)  # 상대를 기다리는 시간보다 다음 말을 기다리는 시간이 길다
        self.assertGreater(area3_chat_rt.LIMITS['deadline'], area3_chat_rt.PEER + 120)

    def test_every_step_that_waits_for_the_pc_after_the_room_opens_follows_a_two_second_wait_for_the_subscription(self):
        """구독이 붙기 전에 PC 가 첫 글을 보내면 1번 글을 놓친다 — PC 를 부르는 첫 step 마다 바로 앞에 2초를 흘린다."""
        lines = [line.strip() for line in self.dart('area3_chat_rt.dart').split('\n')]
        wait, checked = 'await wait(tester, const Duration(seconds: 2));', []
        for i, line in enumerate(lines):
            if re.match(r"await (step\('(stream|sent|cut|home|ready)'|_rtStep\('ready')", line):
                before = [x for x in lines[:i] if x and not x.startswith('//')]
                self.assertTrue(before[-1].startswith(wait), line)
                checked.append(line)
        self.assertEqual(len(checked), 10)  # stream · sent · cut ×3 · home · ready(61) · _rtStep ready ×3

    def function_body(self, name):
        text = self.dart('area3_chat_rt.dart')
        start = text.index(f' {name}(')
        return text[start:text.index('\n}\n', start)]

    def test_no_case_presses_the_retry_button_with_the_plain_tap(self):
        """`tap` 은 확인 → ensureVisible → pump → 다시 찾아 누르는 순서라, 그 pump 사이 배너가 내려가면 "Bad state: No element" 로 앱이 값을 못 말한다(실기기 E-CHAT-24)."""
        text = self.dart('area3_chat_rt.dart')
        self.assertNotIn('tap(tester, find.text(_rtRetry))', text)
        for name in ('_rtMissed', '_rtReconnect'):
            body = self.function_body(name)
            self.assertIn('retried = await _rtTryRetry(tester);', body, name)
            self.assertNotIn('_rtRetry', body, name)  # 버튼 글자는 도우미만 안다

    def test_the_retry_helper_looks_again_after_the_pump_and_does_not_hide_errors(self):
        body = self.function_body('_rtTryRetry')
        first, pump, second, press = (body.index('if (!_has(retry)) return false;'), body.index('await tester.pump();'),
                                      body.rindex('if (!_has(retry)) return false;'), body.index('tester.tap('))
        self.assertLess(first, body.index('ensureVisible'))
        self.assertLess(body.index('ensureVisible'), pump)
        self.assertLess(pump, second)  # pump 뒤에 다시 있는지 본다
        self.assertLess(second, press)
        self.assertIn('warnIfMissed: false', body)
        self.assertIn('return true;', body)
        self.assertNotIn('catch', body)  # 예외를 삼켜 결과를 숨기지 않는다 — 존재 확인으로
        self.assertNotIn('try {', body)

    def alternate_body(self):
        text = self.dart('area3_chat_rt.dart')
        start = text.index('Future<Map<String, Object?>?> _rtAlternate(')
        return text[start:text.index('\n}\n', start)]

    def test_the_alternating_app_warms_the_input_path_before_ready_without_sending(self):
        """에뮬이 처음 입력(IME · 키보드 · 첫 프레임)을 하는 동안 수신 처리가 밀리지 않게 — ready 에서 서기 전에 쓰고 비우고 가라앉힌다. 보내지 않는다(DB 줄이 늘면 안 된다)."""
        body = self.alternate_body()
        ready = body.index("_rtStep('ready'")
        write = body.index('await type(tester, _chatField, _rtWarmText);')
        clear = body.index("await type(tester, _chatField, '');")
        settle = body.index('await wait(tester, const Duration(seconds: 3));')
        self.assertLess(write, clear)
        self.assertLess(clear, settle)
        self.assertLess(settle, ready)
        self.assertNotIn('_sendButton', body[:ready])  # 데우기에서는 보내기를 안 누른다
        self.assertNotIn('onSend', body)
        self.assertRegex(self.dart('area3_chat_rt.dart'), r"const _rtWarmText = '[^']+';")

    def test_the_alternating_app_tells_the_pc_when_it_pressed_send(self):
        body = self.alternate_body()
        self.assertIn('final sentAt = <String>[];', body)
        self.assertLess(body.index('sentAt.add(_utcNow());'), body.index('await tap(tester, _sendButton);'))  # 누르기 직전
        self.assertIn("'sent_at': sentAt", body)
        self.assertLess(body.index("_rtStep('ready'"), body.index('sentAt.add(_utcNow());'))

    def test_the_alternating_app_stands_at_sent_after_its_own_sends_and_only_then_waits_for_all_forty(self):
        body = self.alternate_body()
        loop_end = body.index('await tap(tester, _sendButton);')
        sent = body.index("_rtStep('sent'")
        waiting = body.index('watch.seen.length == all.length')
        done_at = body.index('final doneAt = _utcNow();')
        done = body.index("_rtStep('done'")
        self.assertLess(loop_end, sent)
        self.assertLess(sent, waiting)  # 상대가 다 보낸 뒤부터 20초를 센다
        self.assertLess(waiting, done_at)
        self.assertLess(done_at, done)
        self.assertIn("timeout: _rtLong", body[sent:sent + 120])
        self.assertIn("'done_at': doneAt", body[done:])
        self.assertIn("'sent_at': sentAt", body[done:])
        self.assertIn("'seen': watch.seen", body[done:])
        self.assertIn("'order':", body[done:])
        self.assertIn('const Duration(seconds: 20)', body[waiting:done_at])  # 기다림 상한은 그대로 20초

    def test_every_job_key_is_read_by_the_app(self):
        dart = ''.join(self.dart(n) for n in ('area3.dart', 'area3_b2.dart', 'area3_chat_rt.dart'))
        for key in ('token_hash', 'nickname', 'bodies', 'variant', 'kakao', 'line', 'text', 'mine', 'theirs', 'offset', 'gap'):
            self.assertIn(f"job['{key}']", dart, key)

    def test_the_app_has_the_same_numbers_in_order_and_area3_merges_them(self):
        part = self.dart('area3_chat_rt.dart')
        self.assertTrue(part.startswith("part of 'area3.dart';"))
        keys = re.findall(r"^  '(E-[A-Z]+-\d+(?:/[AB])?)'", part, re.M)
        self.assertEqual(keys, ['E-CHAT-01', 'E-CHAT-02', 'E-CHAT-03/A', 'E-CHAT-03/B', 'E-CHAT-07', 'E-CHAT-22', 'E-CHAT-23', 'E-CHAT-24',
                                'E-CHAT-58/A', 'E-CHAT-58/B', 'E-CHAT-61', 'E-CHAT-72'])
        self.assertEqual(sorted({k.split('/')[0] for k in keys}), sorted(PHONE + TWO))
        main = self.dart('area3.dart')
        self.assertIn("part 'area3_chat_rt.dart';", main)
        self.assertIn('...area3CasesChatRt,', main)
        self.assertLess(main.index('...area3Cases8,'), main.index('...area3CasesChatRt,'))

    def test_every_top_level_name_in_the_app_starts_with_rt_and_is_not_declared_elsewhere(self):
        names = lambda text: set(re.findall(r'^(?=\S)[A-Za-z<>?,\' ]+? (_[A-Za-z0-9]+)\b', text, re.M))  # noqa: E731 — 줄 맨 앞(최상위) 선언만
        part = self.dart('area3_chat_rt.dart')
        mine = names(part)
        self.assertTrue(mine)
        self.assertTrue(all(n.startswith('_rt') for n in mine), mine)
        self.assertIn('area3CasesChatRt', part)
        for other in ('area3.dart', 'area3_b2.dart', 'area3_b3.dart', 'area3_b4.dart', 'area3_b5.dart', 'area3_b8.dart', 'area3_safe.dart'):
            self.assertFalse(mine & names(self.dart(other)), other)

    def test_the_cut_cases_use_the_airplane_mode_path_of_e_chat_25(self):
        source = (tools.ROOT / 'e2e' / 'area3_chat_rt.py').read_text(encoding='utf-8')
        self.assertIn('area4._offline', source)
        self.assertIn('area4._cut(phone)', source)


if __name__ == '__main__':
    unittest.main()
