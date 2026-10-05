"""영역 2 기기 · 시각 가설 13개(area2_time_device.py)의 PC 쪽 시험 — 폰 · 운영 없이 가짜 앱 · 가짜 서버 · 가짜 알림창으로 돈다.
저장소 루트에서 `python -m unittest e2e.test_area2_time_device`.

가짜 서버 [World] 는 표(`/rest/v1/<표>`)를 메모리에 들고 있고, **운영 PostgREST 처럼 없는 열 · 없는 표를 400 · 404 로 돌려준다**
(E-CARD-35 는 없는 `id` 열을 골라 운영에서만 400 이 났다). 열 목록은 supabase/migrations 에서 옮겼다.
배치는 `area2._batch` 를, 알림은 `notify` 모듈을, 시계는 `td.now_seoul` 을 갈아 끼운다."""

import json
import re
import tempfile
import time
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from unittest import mock

from e2e import area1, area2, area2_time_device as td, batch_gate, notify, tools
from e2e.area1 import SEOUL
from e2e.test_area1_phone import CHROME, OURS, FakePhone
from e2e.test_area2 import Base
from e2e.test_area3 import Fake
from e2e.tools import Blocked, Reply

CARD = ('오늘의 카드가 도착했어요', '지금 확인해 보세요')


def seoul(month, day, hour, minute=0, second=0):
    return datetime(2026, month, day, hour, minute, second, tzinfo=SEOUL)


# 2026-10-05 는 월요일
MON, TUE, WED, SUN = (lambda h, m=0, s=0, d=d: seoul(10, d, h, m, s) for d in (5, 6, 7, 11))


class WindowTest(unittest.TestCase):
    def test_night_window_is_22_to_2359_and_a_refusal_names_when_to_come_back(self):
        self.assertIsNone(td.night_refusal(TUE(22, 0)))
        self.assertIsNone(td.night_refusal(TUE(23, 59)))
        self.assertEqual(td.night_refusal(TUE(21, 59)), '지금은 실행 금지 시간 — 22:00 에 다시')
        self.assertEqual(td.night_refusal(TUE(8, 0)), '지금은 실행 금지 시간 — 22:00 에 다시')

    def test_night_window_for_the_card_batch_skips_monday_because_daily_cards_is_shut_all_monday(self):
        self.assertIsNone(td.night_refusal(MON(22, 30)))  # 배치를 안 부르는 단계(E-CARD-44 1단계)는 월요일 밤도 된다
        self.assertEqual(td.night_refusal(MON(22, 30), skip_monday=True), '지금은 실행 금지 시간 — 화요일 22:00 에 다시')
        self.assertEqual(td.night_refusal(MON(9, 0), skip_monday=True), '지금은 실행 금지 시간 — 화요일 22:00 에 다시')
        self.assertIsNone(td.night_refusal(TUE(22, 30), skip_monday=True))

    def test_monday_morning_window_is_0640_to_0658_and_only_on_monday(self):
        self.assertIsNone(td.monday_morning_refusal(MON(6, 40)))
        self.assertIsNone(td.monday_morning_refusal(MON(6, 58, 59)))
        self.assertEqual(td.monday_morning_refusal(MON(6, 39, 59)), '지금은 실행 금지 시간 — 06:50 에 다시')
        self.assertEqual(td.monday_morning_refusal(MON(6, 59)), '지금은 실행 금지 시간 — 월요일 06:50 에 다시')
        self.assertEqual(td.monday_morning_refusal(TUE(6, 50)), '지금은 실행 금지 시간 — 월요일 06:50 에 다시')

    def test_before_midnight_window_is_2340_to_2358_on_any_day(self):
        self.assertIsNone(td.midnight_refusal(WED(23, 40)))
        self.assertIsNone(td.midnight_refusal(WED(23, 58, 59)))
        self.assertEqual(td.midnight_refusal(WED(23, 59)), '지금은 실행 금지 시간 — 목요일 23:50 에 다시')
        self.assertEqual(td.midnight_refusal(WED(12, 0)), '지금은 실행 금지 시간 — 23:50 에 다시')


class Card44StepTest(unittest.TestCase):
    NIGHT = {'night_date': '2026-10-06'}  # 화요일 밤에 1단계를 끝냈다

    def test_with_no_state_only_the_night_window_starts_stage_one(self):
        self.assertEqual(td.card44_step(TUE(22, 30), None), ('night', None))
        self.assertEqual(td.card44_step(WED(9, 0), None), (None, '지금은 실행 금지 시간 — 22:00 에 다시'))

    def test_next_morning_after_0810_the_same_number_runs_stage_two(self):
        self.assertEqual(td.card44_step(WED(8, 10), self.NIGHT), ('morning', None))
        self.assertEqual(td.card44_step(WED(21, 49), self.NIGHT), ('morning', None))

    def test_before_0810_the_morning_stage_is_refused_with_0810(self):
        want = (None, '지금은 실행 금지 시간 — 08:10 에 다시')
        self.assertEqual(td.card44_step(WED(8, 9), self.NIGHT), want)
        self.assertEqual(td.card44_step(WED(0, 30), self.NIGHT), want)

    def test_from_2150_the_morning_is_over_and_the_answer_is_the_night_stage_again(self):
        # 아침 알림은 08시 예약 배치가 이미 보냈고 사라졌을 수 있다 — 저녁에는 아침 단계를 안 돌리고 새 1단계로 안내한다
        self.assertEqual(td.card44_step(WED(21, 50), self.NIGHT), (None, '지금은 실행 금지 시간 — 22:00 에 다시'))

    def test_the_same_night_the_first_stage_may_be_run_again(self):
        self.assertEqual(td.card44_step(TUE(23, 30), self.NIGHT), ('night', None))

    def test_a_state_two_days_old_is_ignored_so_the_morning_stage_is_not_run_on_it(self):
        self.assertEqual(td.card44_step(seoul(10, 8, 9, 0), self.NIGHT), (None, '지금은 실행 금지 시간 — 22:00 에 다시'))
        self.assertEqual(td.card44_step(seoul(10, 8, 22, 30), self.NIGHT), ('night', None))

    def test_a_finished_state_means_the_next_night_starts_over(self):
        done = {**self.NIGHT, 'done': True}
        self.assertEqual(td.card44_step(WED(9, 0), done), (None, '지금은 실행 금지 시간 — 22:00 에 다시'))
        self.assertEqual(td.card44_step(WED(22, 30), done), ('night', None))

    def test_on_the_next_evening_the_night_stage_wins_over_the_old_pending_state(self):
        self.assertEqual(td.card44_step(WED(22, 30), self.NIGHT), ('night', None))


class MondayTest(unittest.TestCase):
    def test_past_monday_is_at_least_an_hour_before_now_and_a_monday_0700_seoul(self):
        for now in (MON(6, 0), MON(7, 30), MON(12, 0), TUE(12, 0), WED(1, 0), SUN(23, 59)):
            got = td.past_monday(now)
            self.assertEqual((got.weekday(), got.hour, got.minute, got.second), (0, 7, 0, 0), now)
            self.assertEqual(got.utcoffset(), timedelta(hours=9))
            self.assertLessEqual(got, now - timedelta(hours=1), now)
            self.assertGreater(got, now - timedelta(days=8), now)

    def test_on_a_monday_after_0700_it_is_that_same_monday_but_before_0800_it_is_last_week(self):
        self.assertEqual(td.past_monday(MON(12, 0)), MON(7, 0))
        self.assertEqual(td.past_monday(MON(7, 30)), seoul(9, 28, 7, 0))

    def test_future_monday_is_a_monday_0700_at_least_min_days_calendar_days_ahead(self):
        for now in (MON(6, 0), MON(12, 0), TUE(12, 0), SUN(23, 59), seoul(10, 10, 23, 58)):
            for days in (1, 2):
                got = td.future_monday(now, days)
                self.assertEqual((got.weekday(), got.hour, got.minute), (0, 7, 0), (now, days))
                self.assertGreaterEqual((got.date() - now.date()).days, days, (now, days))
                self.assertLess((got.date() - now.date()).days, days + 7, (now, days))
                self.assertGreater(got, now)

    def test_friday_with_two_days_gives_next_monday_and_sunday_with_two_days_skips_to_the_one_after(self):
        self.assertEqual(td.future_monday(seoul(10, 9, 12), 2), seoul(10, 12, 7))  # 금 → 다음 월(3일 뒤)
        self.assertEqual(td.future_monday(SUN(12), 2), seoul(10, 19, 7))  # 일 → 내일 월은 1일 뒤라 모자라다


class ParseTest(unittest.TestCase):
    def test_the_app_is_waited_for_until_its_deadline_plus_two_minutes_not_a_fixed_time(self):
        # 06:41 에 시작한 E-HOME-24 는 07:04 마감까지 23분 — 고정 15분이면 앱이 아직 서 있는데 PC 가 먼저 포기한다
        self.assertEqual(td.app_timeout(MON(6, 41), MON(7, 4)), 23 * 60 + 120)
        self.assertEqual(td.app_timeout(MON(7, 5), MON(7, 4)), 120)  # 마감이 지났어도 앱 답을 듣는 최소 시간

    def test_notification_permission_state_is_read_from_dumpsys_package(self):
        on = '    android.permission.POST_NOTIFICATIONS: granted=true, flags=[ USER_SET]'
        off = 'runtime permissions:\n    android.permission.POST_NOTIFICATIONS: granted=false, flags=[ REVOKED_COMPAT]\n'
        self.assertIs(td.notifications_granted(on), True)
        self.assertIs(td.notifications_granted(off), False)
        self.assertIsNone(td.notifications_granted('android.permission.CAMERA: granted=true'))
        self.assertIsNone(td.notifications_granted(''))

    def test_epoch_ms_is_the_instant_not_the_wall_clock(self):
        self.assertEqual(td.epoch_ms(datetime(1970, 1, 1, 9, 0, 1, tzinfo=SEOUL)), 1000)


# ── 가짜 세계 ───────────────────────────────────────────────────────────────────────────────────────

# supabase/migrations 에서 옮긴 열 목록 — 시험이 고르는 열 · 거는 필터가 여기 없으면 가짜 서버가 운영처럼 400 을 준다.
COLUMNS = {
    'push_tokens': {'token', 'profile_id', 'platform', 'updated_at'},  # 20260920160547
    'daily_cards': {'id', 'owner_id', 'target_id', 'source', 'issued_at', 'expires_at'},  # 20260920160537
    'pending_pushes': {'id', 'profile_id', 'kind', 'title', 'body', 'data', 'created_at'},  # 20261003010000
    'universities': {'id', 'name', 'region_group', 'created_at', 'card_opens_at'},  # 20260913054542 · 20260928050000
    'region_group_settings': {'region_group', 'issue_weekdays', 'issue_time', 'ladder_twice_per_week_min', 'ladder_three_per_week_min',
                              'ladder_four_per_week_min', 'ladder_daily_min', 'updated_at'},  # 20260920160540 · 20261003020000
    'profiles': {'id', 'university_id', 'nickname', 'gender', 'birth_year', 'status', 'last_active_at', 'created_at', 'matching_paused'},
}
EMBEDS = {'profiles': {'universities'}, 'daily_cards': {'card_decisions'}}
HELPER_TABLES = {'profile_vectors', 'profile_private', 'profile_avatars'}  # 계정 공장(Run.account) · 사람 만들기 도우미가 쓰는 표 — 열은 그쪽 시험이 본다
BODY_CHECKED = {'daily_cards', 'universities', 'region_group_settings'}  # 쓰는 본문 열도 검사하는 표
RESERVED = {'select', 'order', 'limit', 'offset', 'or', 'and', 'on_conflict'}
SETTINGS = {'card_arrived': True, 'acceptance_received': True, 'match_made': True, 'new_message': True, 'trust_reminder': True,
            'new_friend_review': True, 'marketing': False, 'quiet_hours': True}  # backend NOTIFICATION_DEFAULTS
ROW = {'region_group': 'e2e', 'issue_weekdays': [1], 'issue_time': '07:00:00', 'ladder_twice_per_week_min': 50,
       'ladder_three_per_week_min': 500, 'ladder_four_per_week_min': 1000, 'ladder_daily_min': 2000}


def select_names(select):
    """`a,b,universities(region_group)` → [('a', False), ('b', False), ('universities', True)] — 괄호 안 쉼표는 가르지 않는다."""
    items, depth, word = [], 0, ''
    for char in select + ',':
        if char == ',' and depth == 0:
            if word:
                items.append((word.split('(')[0], '(' in word))
            word = ''
            continue
        depth += {'(': 1, ')': -1}.get(char, 0)
        word += char
    return items


class World(Fake):
    """표 저장소 + 열 검사 + 미니 서버(알림 설정 · 수락 · 후보 · 오늘 카드). 알림은 [shade](폰 알림창)에 쌓인다.
    계정은 만든 순서대로 id-1 · id-2 …, 토큰은 tok-1 · tok-2 …, 닉네임은 `닉<id>`."""

    def __init__(self):
        super().__init__()
        self.tables.update({'region_group_settings': [dict(ROW)],
                            'universities': [{'id': 'U', 'name': '테스트대학', 'region_group': 'e2e', 'card_opens_at': None}]})
        self.shade, self.settings, self.pool, self.rejected = [], {}, ['id-2'], []
        self.night, self.defer, self.drop, self.on_link, self.ignore_rest = False, True, False, None, False
        self.permitted = lambda: True  # 폰의 알림 권한 — 빠졌으면 서버가 보내도 알림창에 안 뜬다(안드로이드 13+)
        for method, pattern, reply in (
            ('GET', r'/cards/notification-settings', self.get_settings), ('PATCH', r'/cards/notification-settings', self.patch_settings),
            ('POST', r'/cards/[^/]+/decision', self.decide), ('GET', r'/matching/candidates', self.candidates),
            ('GET', r'/cards/today', self.today), ('POST', r'/auth/v1/admin/generate_link', self.link),
        ):
            self.on(method, pattern, reply)

    # 열 · 표 이름 검사(운영 PostgREST 와 같은 400 · 404)
    def _table(self, method, name, sent):
        if name not in COLUMNS and name not in HELPER_TABLES:
            self.rejected.append((name, '표'))
            return Reply(404, {'code': 'PGRST205', 'message': f"Could not find the table 'public.{name}' in the schema cache"})
        if name in COLUMNS:
            used, query = set(), sent['query']
            for column, embedded in select_names(query.get('select', '')):
                if column != '*' and column not in (EMBEDS.get(name, set()) if embedded else COLUMNS[name]):
                    used.add(column)
            used |= {key for key in query if key not in RESERVED and key not in COLUMNS[name]}
            body = sent['body']
            if method in ('POST', 'PATCH') and name in BODY_CHECKED:
                used |= {key for row in (body if isinstance(body, list) else [body]) for key in row if key not in COLUMNS[name]}
            if used:
                self.rejected.append((name, sorted(used)[0]))
                return Reply(400, {'code': '42703', 'message': f'column {name}.{sorted(used)[0]} does not exist'})
        if name == 'profiles' and method == 'GET':
            pid = sent['query'].get('id', '')[3:]
            return Reply(200, [{'id': pid, 'nickname': f'닉{pid}', 'status': self.statuses.get(pid, 'active'),
                                'universities': {'region_group': 'e2e'}}])
        return super()._table(method, name, sent)

    def owner_of(self, sent):
        return 'id-' + sent['auth'].split('-')[1]

    def link(self, sent):
        if self.on_link:
            self.on_link()
        return Reply(200, {'hashed_token': 'h-' + sent['body']['email']})

    def get_settings(self, sent):
        return Reply(200, {**SETTINGS, **self.settings.get(self.owner_of(sent), {})})

    def patch_settings(self, sent):
        self.settings.setdefault(self.owner_of(sent), {}).update(sent['body'])
        return Reply(200, {'ok': True})

    def rested(self, owner):
        return {c['target_id'] for c in self.tables.get('daily_cards', []) if c['owner_id'] == owner}

    def candidates_of(self, owner):
        return [p for p in self.pool if self.ignore_rest or p not in self.rested(owner)]

    def candidates(self, sent):
        return Reply(200, {'candidates': [{'profile_id': p, 'score': 0.5} for p in self.candidates_of(self.owner_of(sent))]})

    def live_cards(self, owner):
        now = datetime.now(SEOUL)
        return [c for c in self.tables.get('daily_cards', []) if c['owner_id'] == owner and datetime.fromisoformat(c['expires_at']) > now]

    def today(self, sent):
        owner = self.owner_of(sent)
        return Reply(200, {'cards': self.live_cards(owner), 'candidate_pool_empty': not self.live_cards(owner) and not self.candidates_of(owner)})

    def post(self, title, text):
        self.shade.append(notify.Notice(f'k{len(self.shade)}', title, text, 'c'))

    def give_card(self, owner, target='id-9', days=1):
        self.tables.setdefault('daily_cards', []).append({
            'id': f'card-{len(self.tables.get("daily_cards", []))}', 'owner_id': owner, 'target_id': target, 'source': 'daily',
            'issued_at': datetime.now(SEOUL).isoformat(), 'expires_at': (datetime.now(SEOUL) + timedelta(days=days)).isoformat()})

    def decide(self, sent):
        """수락이면 받는 사람(카드의 target)에게 알림 — 방해 금지 시간(밤)이고 그 사람이 켜 뒀으면 보관함, 아니면 바로 알림창."""
        card = next(c for c in self.tables['daily_cards'] if c['id'] == sent['path'].split('/')[2])
        if sent['body']['decision'] == 'accept' and not (self.night and self.drop):
            target, text = card['target_id'], f"닉{card['owner_id']} 님이 대화를 하고 싶어 해요"
            if self.night and self.defer and {**SETTINGS, **self.settings.get(target, {})}['quiet_hours']:
                self.tables.setdefault('pending_pushes', []).append({
                    'id': f'p{len(self.tables.get("pending_pushes", []))}', 'profile_id': target, 'kind': 'acceptance_received',
                    'title': td.NIGHT_TITLE, 'body': text, 'data': {'route': 'acceptances'}})
            elif self.permitted():
                self.post(td.NIGHT_TITLE, text)
        return Reply(200, {'ok': True})

    def send_pending(self):
        """08시 뒤 chat-gate 가 보관함을 비우고 원문 알림을 보낸다(한 건이면 원문)."""
        for row in self.tables.get('pending_pushes', []):
            if self.permitted():
                self.post(row['title'], row['body'])
        self.tables['pending_pushes'] = []


class AppPhone(FakePhone):
    """앱 대신 답한다 — 로그인(token_hash)하면 그 계정의 기기 토큰이 서버에 올라온 것으로 친다([push_token=False] 면 안 올라옴)."""

    def __init__(self, world, *answers, push_token=True, serial='S', **kw):
        super().__init__(*answers, **kw)
        self.world, self.push_token, self.serial, self.hub = world, push_token, serial, mock.Mock()

    def __call__(self, midway=None, **job):
        if job.get('token_hash') and self.push_token:
            who = next(u['id'] for u in self.world.users if u['email'] == job['token_hash'][2:])
            self.world.tables.setdefault('push_tokens', []).append({'token': f't-{who}', 'profile_id': who, 'platform': 'android'})
        return super().__call__(midway, **job)


class Clock:
    def __init__(self, now):
        self.now = now


ORIGINAL_BATCH = area2._batch


class DeviceBase(Base):
    """가짜 세계 + 가짜 알림창 + 가짜 배치 + 가짜 시계 위에서 가설 하나를 돌린다."""

    START = TUE(12)

    def setUp(self):
        super().setUp()
        self.world, self.clock = World(), Clock(self.START)
        self.reset()
        self.world.permitted = lambda: self.granted
        for patcher in (
            mock.patch.object(tools, 'call', self.world), mock.patch.object(area2, '_batch', self.batch),
            mock.patch.object(notify, 'grant_notifications', self.grant), mock.patch.object(notify, 'revoke_notifications', self.revoke),
            mock.patch.object(notify, 'read_notifications', self.read), mock.patch.object(notify, 'background', self.home),
            mock.patch.object(notify, 'wait_new', self.wait_new), mock.patch.object(notify, 'expect_none', self.expect_none),
            mock.patch.object(notify, 'ensure_delivery', self.prepare),
            mock.patch.object(tools, 'adb', self.adb), mock.patch.object(tools.Run, 'shot', lambda run, serial, case: None),  # 실패 때 화면 캡처(adb)를 안 부른다
            mock.patch.object(td, 'now_seoul', lambda: self.clock.now),
            mock.patch.object(time, 'sleep', lambda s: None), mock.patch.object(time, 'monotonic', side_effect=iter(range(0, 10 ** 6))),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    def reset(self):
        self.log, self.batches, self.windows, self.scripts, self.granted, self.skew = [], [], [], {}, True, 0
        self.prepared, self.prepare_error = [], None  # 푸시 연결 점검(notify.ensure_delivery) 호출: (기기, 그때까지 만든 계정 수)

    # 가짜 기기 · 알림창
    def prepare(self, serial):
        self.prepared.append((serial, len(self.world.users)))
        if self.prepare_error:
            raise self.prepare_error

    def batch(self, name):
        self.log.append(f'batch:{name}')
        self.batches.append(name)
        if name in self.scripts:
            self.scripts[name]()

    def grant(self, serial):
        self.log.append('grant')
        self.granted = True

    def revoke(self, serial):
        self.log.append('revoke')
        self.granted = False

    def read(self, serial):
        self.log.append('read')
        return list(self.world.shade)

    def home(self, serial):
        self.log.append('home')

    def fresh(self, before):
        seen = {n.key for n in before}
        return [n for n in self.world.shade if n.key not in seen]

    def wait_new(self, serial, before, count=1, seconds=0):
        self.windows.append(('new', seconds))
        return self.fresh(before)

    def expect_none(self, serial, before, seconds=0):
        self.windows.append(('none', seconds))
        return self.fresh(before)

    def adb(self, serial, *args, check=True):
        if args[:3] == ('shell', 'dumpsys', 'package'):
            return f'    android.permission.POST_NOTIFICATIONS: granted={str(self.granted).lower()}, flags=[ USER_SET]\n'
        if args[:3] == ('shell', 'date', '+%s'):
            return str(int(self.clock.now.timestamp()) + self.skew)
        return ''

    def phone(self, *answers, **kw):
        return AppPhone(self.world, *answers, **kw)

    def go(self, case, phone):
        result = area1.attempt_phone(self.run, case, phone)
        self.assertEqual(self.world.rejected, [], '가설이 없는 열 · 표를 물었다(운영이면 400 · 404)')
        return result

    def region_patches(self):
        return [s['body'] for s in self.world.by('PATCH', '/rest/v1/region_group_settings')]

    def opens_patches(self):
        return [s['body']['card_opens_at'] for s in self.world.by('PATCH', '/rest/v1/universities')]

    def issue_to(self, *owners, notice=True):
        """미니 서버의 카드 배치 — [owners] 에게 카드를 주고, 폰(알림 권한이 있을 때만)에 도착 알림."""
        def run():
            for owner in owners:
                self.world.give_card(owner)
            if notice and self.granted:
                self.world.post(*CARD)
        return run


DAILY_CARDS_CASES = ['E-CARD-01', 'E-CARD-03', 'E-CARD-13', 'E-CARD-18', 'E-CARD-19', 'E-CARD-20', 'E-HOME-29']


# 알림이 오는지 · 안 오는지를 판정하는 가설 → (시계, 폰 인자). 푸시 연결이 죽은 폰에서는 FCM 200 인데도 안 떠서 "안 온다" 가설이 헛통과한다.
PUSH_CASES = {
    'E-CARD-01': (TUE(12), {}), 'E-CARD-03': (TUE(12), {'top': OURS, 'midway_step': {'step': 'live'}}),
    'E-CARD-17': (TUE(22, 30), {}), 'E-CARD-18': (TUE(12), {}), 'E-CARD-19': (TUE(12), {}),
    'E-CARD-20': (TUE(12), {'serial': 'emulator-5554'}), 'E-HOME-29': (WED(12), {'serial': 'emulator-5554'}),
}
# 알림을 안 보는 가설(코호트 시계 · 후보 0 화면) — 기기를 건드리는 점검(Wi-Fi 껐다 켜기)을 하지 않는다
NO_PUSH_CASES = {'E-CARD-13': TUE(12), 'E-HOME-23': TUE(12), 'E-HOME-24': MON(6, 50), 'E-HOME-25': TUE(23, 50), 'E-HOME-26': TUE(12)}


class DeliveryTest(DeviceBase):
    def start(self, case, now, kw, error=None):
        self.reset()
        self.prepare_error = error  # reset 이 비운 뒤에 건다
        self.world = World()
        self.world.permitted = lambda: self.granted
        self.clock.now = now
        self.scripts['daily-cards'] = lambda: None
        phone = self.phone(**kw)
        with mock.patch.object(tools, 'call', self.world):
            return self.go(case, phone), phone

    def test_each_case_that_judges_a_push_checks_the_push_connection_once_before_any_account(self):
        for case, (now, kw) in PUSH_CASES.items():
            with self.subTest(case=case):
                _, phone = self.start(case, now, kw)
                self.assertEqual(self.prepared, [(phone.serial, 0)])  # 계정 0개일 때 — 점검이 실패하면 계정을 만들지 않는다

    def test_a_dead_push_connection_ends_blocked_before_any_account_app_permission_or_batch(self):
        for case, (now, kw) in PUSH_CASES.items():
            with self.subTest(case=case):
                (result, note), phone = self.start(case, now, kw, error=Blocked('GCM 연결 횟수를 못 읽음 — 푸시 연결을 점검할 수 없음'))
                self.assertEqual((result, note), ('blocked', 'GCM 연결 횟수를 못 읽음 — 푸시 연결을 점검할 수 없음'))
                self.assertEqual((self.world.users, phone.jobs, self.batches, self.log), ([], [], [], []))

    def test_card_20_on_a_real_phone_is_blocked_before_the_wifi_is_touched(self):
        (result, _), phone = self.start('E-CARD-20', TUE(12), {'serial': 'R58N1234'})
        self.assertEqual(result, 'blocked')
        self.assertEqual((self.prepared, self.world.users), ([], []))  # 에뮬레이터 요건이 먼저 — 실기기의 Wi-Fi 를 껐다 켜지 않는다

    def test_a_case_refused_by_the_clock_does_not_touch_the_phone_connection(self):
        for case, now in (('E-CARD-01', MON(12)), ('E-CARD-17', TUE(12)), ('E-CARD-18', TUE(3, 0)), ('E-HOME-29', MON(9))):
            with self.subTest(case=case):
                _, phone = self.start(case, now, PUSH_CASES[case][1])
                self.assertEqual(self.prepared, [])  # 시각 규칙에 막히면 Wi-Fi 도 안 껐다 켠다

    def test_cases_that_do_not_look_at_notifications_never_prepare_the_push_connection(self):
        for case, now in NO_PUSH_CASES.items():
            with self.subTest(case=case):
                self.start(case, now, {'serial': 'emulator-5554'} if case.startswith('E-HOME') else {})
                self.assertEqual(self.prepared, [])
                self.assertTrue(self.world.users, '가설이 시작 단계에서 막혀 점검 여부를 못 봤다')

    def test_card_44_checks_it_in_both_steps_and_a_dead_connection_blocks_each(self):
        self.reset()
        self.world = World()
        self.world.permitted = lambda: self.granted
        self.world.night = True
        self.scripts['chat-gate'] = self.world.send_pending
        self.clock.now = TUE(22, 30)
        with mock.patch.object(tools, 'call', self.world):
            night = self.phone()
            self.go('E-CARD-44', night)
            self.assertEqual(self.prepared, [(night.serial, 0)])
            self.world.night, self.clock.now = False, WED(9, 20)
            morning = self.phone()
            self.go('E-CARD-44', morning)
        self.assertEqual([s for s, _ in self.prepared], [night.serial, morning.serial])

    def test_a_dead_connection_in_the_morning_leaves_the_state_file_and_the_permission_untouched(self):
        self.world.night = True
        self.scripts['chat-gate'] = self.world.send_pending
        self.clock.now = TUE(22, 30)
        night_phone = self.phone()
        self.go('E-CARD-44', night_phone)
        state = (self.run.out / 'card44_state.json').read_text(encoding='utf-8')
        self.world.night, self.clock.now = False, WED(9, 20)
        self.prepare_error = Blocked('GCM 연결 횟수를 못 읽음 — 푸시 연결을 점검할 수 없음')
        log_before = list(self.log)
        result = self.go('E-CARD-44', self.phone())
        self.assertEqual(result[0], 'blocked')
        self.assertEqual((self.run.out / 'card44_state.json').read_text(encoding='utf-8'), state)  # 같은 번호로 다시 돌릴 수 있게
        self.assertEqual(self.log, log_before)  # 점검이 실패하면 권한을 건드리지도 배치를 부르지도 않는다


class DailyCardsGateTest(DeviceBase):
    def test_a_case_that_calls_daily_cards_is_refused_before_any_account_on_a_monday_or_before_0710(self):
        shut = {MON(12): '지금은 실행 금지 시간 — 화요일 07:11 에 다시', TUE(3, 0): '지금은 실행 금지 시간 — 07:11 에 다시'}
        for case in DAILY_CARDS_CASES:
            for now, said in shut.items():
                with self.subTest(case=case, now=now):
                    self.reset()
                    self.world.users.clear()
                    self.clock.now = now
                    phone = self.phone(serial='emulator-5554')
                    self.assertEqual(self.go(case, phone), ('blocked', said))
                    self.assertEqual((self.world.users, phone.jobs, self.batches, self.log), ([], [], [], []))  # 계정 · 앱 · 권한 · 배치 0

    def test_the_same_cases_run_on_an_open_tuesday_noon(self):
        self.scripts['daily-cards'] = self.issue_to('id-1', 'id-2', 'id-3')
        self.assertEqual(self.go('E-CARD-01', self.phone())[0], 'pass')


# 대조군이 없던 가설: (대조군 id, 시계, 폰 인자). 대조군 = 대상과 같은 성별 · 다른 임베딩 축의 별개 계정 하나 — 대상의 후보 풀에 안 끼고 같은 배치에서 카드를 받는다.
CONTROLLED = {
    'E-CARD-01': ('id-3', TUE(12), {}), 'E-CARD-03': ('id-3', TUE(12), {'top': OURS, 'midway_step': {'step': 'live'}}),
    'E-CARD-17': ('id-3', TUE(22, 30), {}), 'E-CARD-18': ('id-3', TUE(12), {}), 'E-CARD-19': ('id-4', TUE(12), {}),
    'E-HOME-29': ('id-3', WED(12), {'serial': 'emulator-5554'}),
}
CONTROL_MISSED = '대조군은 카드를 받았는데 대상은 못 받음'


class ControlTest(DeviceBase):
    def run_case(self, case, script):
        control, now, kw = CONTROLLED[case]
        self.reset()
        self.world = World()  # 계정 번호(id-1 …)가 가설마다 처음부터
        self.world.permitted = lambda: self.granted
        self.clock.now = now
        self.scripts['daily-cards'] = script
        with mock.patch.object(tools, 'call', self.world):
            return self.go(case, self.phone(**kw)), control

    def test_a_control_that_got_a_card_while_the_target_did_not_is_a_fail(self):
        for case, (control, now, kw) in CONTROLLED.items():
            with self.subTest(case=case):
                (result, note), _ = self.run_case(case, lambda c=control: self.world.give_card(c))
                self.assertEqual(result, 'fail', (case, note))
                self.assertIn(CONTROL_MISSED, note)

    def test_nobody_getting_a_card_is_still_blocked_with_the_slow_batch_wording(self):
        for case in CONTROLLED:
            with self.subTest(case=case):
                (result, note), _ = self.run_case(case, lambda: None)
                self.assertEqual(result, 'blocked', (case, note))
                self.assertIn('느린 배치인지 결함인지 구분 못 함', note)

    def test_the_batch_is_called_once_per_batch_the_case_always_made_not_once_more_for_the_control(self):
        self.clock.now = TUE(12)
        self.scripts['daily-cards'] = self.issue_to('id-1', 'id-3')
        self.go('E-CARD-01', self.phone())
        self.assertEqual(self.batches, ['daily-cards'])

    def test_when_both_get_cards_the_exact_one_card_and_one_notice_checks_are_unchanged(self):
        self.scripts['daily-cards'] = self.issue_to('id-1', 'id-3')  # 대조군 카드의 알림은 다른 기기라 이 폰에 안 온다 — 알림은 대상 몫 1건
        result = self.go('E-CARD-01', self.phone())
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(len(self.world.shade), 1)
        self.assertEqual(len(self.world.live_cards('id-1')), 1)

    def test_the_control_is_the_same_gender_as_the_receiver_and_on_another_embedding_axis(self):
        for case, receiver in (('E-CARD-01', 'male'), ('E-HOME-29', 'female')):
            with self.subTest(case=case):
                self.reset()
                self.world = World()
                self.world.permitted = lambda: self.granted
                self.clock.now = CONTROLLED[case][1]
                self.scripts['daily-cards'] = self.issue_to('id-1', 'id-2', 'id-3')
                with mock.patch.object(tools, 'call', self.world):
                    self.go(case, self.phone(**CONTROLLED[case][2]))
                genders = [s['body']['gender'] for s in self.world.by('PATCH', '/rest/v1/profiles') if 'gender' in s['body']]
                self.assertEqual(genders[2], receiver)  # 대조군(세 번째)은 폰 계정과 같은 성별 — 폰 계정의 후보 풀에 안 낀다
                axes = [s['body']['self_embedding'] for s in self.world.by('POST', '/rest/v1/profile_vectors')]
                receiver_axis = axes[0] if receiver == 'male' else axes[1]
                self.assertNotEqual(axes[2], receiver_axis)

    def test_one_extra_account_is_the_whole_cost_of_the_control(self):
        phone = self.phone()
        self.world.on_link = lambda: None
        self.go('E-CARD-01', phone)
        self.assertEqual(len(self.world.users), 3)


class WorldToolTest(DeviceBase):
    def test_the_fake_server_rejects_what_production_postgrest_rejects(self):
        self.assertEqual(self.world._table('GET', 'push_tokens', {'query': {'select': 'id'}, 'body': None}).status, 400)  # 기본키는 token
        self.assertEqual(self.world._table('GET', 'daily_card', {'query': {}, 'body': None}).status, 404)  # 표 이름 오타
        self.assertEqual(self.world._table('GET', 'daily_cards', {'query': {'owner': 'eq.x'}, 'body': None}).status, 400)  # 필터 열
        self.assertEqual(self.world._table('PATCH', 'universities', {'query': {}, 'body': {'opens_at': 1}}).status, 400)  # 본문 열
        self.assertEqual(self.world._table('GET', 'profiles', {'query': {'id': 'eq.x', 'select': 'universities(region_group)'}, 'body': None}).status, 200)
        self.assertEqual(len(self.world.rejected), 4)
        self.world.rejected.clear()


# ── 배치 + 알림 ─────────────────────────────────────────────────────────────────────────────────────

class Card01Test(DeviceBase):
    def setUp(self):
        super().setUp()
        self.scripts['daily-cards'] = self.issue_to('id-1')

    def test_one_card_one_matching_notice_after_login_token_and_home(self):
        phone = self.phone()
        result = self.go('E-CARD-01', phone)
        self.assertEqual(result[0], 'pass', result)
        # 권한 → (로그인) → 알림창을 먼저 읽어 두고(앞 알림과 안 섞이게) → HOME → 배치 → 끝나면 권한을 되돌린다
        self.assertEqual(self.log, ['grant', 'read', 'home', 'batch:daily-cards', 'revoke'])
        self.assertEqual(phone.jobs, [{'token_hash': 'h-' + self.world.users[0]['email']}])  # A(남)로 로그인
        self.assertIn(('new', 30), self.windows)
        self.assertEqual(self.region_patches()[0]['issue_weekdays'], [1, 2, 3, 4, 5, 6, 7])
        self.assertEqual(self.region_patches()[0]['ladder_daily_min'], 0)
        self.assertEqual(self.region_patches()[-1], {k: ROW[k] for k in self.region_patches()[0]})  # 지역 행 원복
        self.assertIn('issued', result[1])  # 응답 수치는 못 읽는다는 메모

    def test_a_notice_with_another_body_is_a_fail(self):
        self.scripts['daily-cards'] = lambda: (self.world.give_card('id-1'), self.world.post(CARD[0], '다른 본문'))
        self.assertEqual(self.go('E-CARD-01', self.phone())[0], 'fail')

    def test_the_same_notice_twice_is_a_fail(self):
        self.scripts['daily-cards'] = lambda: (self.issue_to('id-1')(), self.world.post(*CARD))
        result = self.go('E-CARD-01', self.phone())
        self.assertEqual(result[0], 'fail')
        self.assertIn('2건', result[1])

    def test_two_cards_for_the_owner_is_a_fail(self):
        self.scripts['daily-cards'] = lambda: (self.issue_to('id-1')(), self.world.give_card('id-1'))
        self.assertEqual(self.go('E-CARD-01', self.phone())[0], 'fail')

    def test_no_card_after_the_batch_is_blocked_not_fail_because_a_slow_batch_looks_the_same_and_no_notice_is_waited_for(self):
        self.scripts['daily-cards'] = lambda: None
        result = self.go('E-CARD-01', self.phone())
        self.assertEqual(result[0], 'blocked')
        self.assertIn('느린 배치인지 결함인지 구분 못 함', result[1])
        self.assertNotIn(('new', 30), self.windows)
        self.assertEqual(self.log[-1], 'revoke')

    def test_no_device_token_is_blocked_before_the_batch_and_the_region_row_is_put_back(self):
        result = self.go('E-CARD-01', self.phone(push_token=False))
        self.assertEqual(result[0], 'blocked')
        self.assertEqual(self.batches, [])
        self.assertEqual(self.log[-1], 'revoke')
        self.assertEqual(self.region_patches()[-1], {k: ROW[k] for k in self.region_patches()[0]})


class Card17Test(DeviceBase):
    START = TUE(22, 30)

    def setUp(self):
        super().setUp()
        self.scripts['daily-cards'] = self.issue_to('id-1')

    def test_outside_the_night_window_nothing_is_created_and_the_phone_is_not_called(self):
        self.clock.now = TUE(12)
        phone = self.phone()
        result = self.go('E-CARD-17', phone)
        self.assertEqual(result, ('blocked', '지금은 실행 금지 시간 — 22:00 에 다시'))
        self.assertEqual((phone.jobs, self.world.users, self.batches), ([], [], []))

    def test_monday_night_is_refused_because_daily_cards_is_shut_all_monday(self):
        self.clock.now = MON(22, 30)
        result = self.go('E-CARD-17', self.phone())
        self.assertEqual(result, ('blocked', '지금은 실행 금지 시간 — 화요일 22:00 에 다시'))

    def test_the_notice_arrives_at_night_with_quiet_hours_on(self):
        result = self.go('E-CARD-17', self.phone())
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.batches, ['daily-cards'])
        self.assertEqual(self.world.by('PATCH', '/cards/notification-settings'), [])  # 기본값(켬)을 건드리지 않았다

    def test_quiet_hours_that_are_off_make_the_exception_meaningless_so_blocked(self):
        self.world.settings['id-1'] = {'quiet_hours': False}
        result = self.go('E-CARD-17', self.phone())
        self.assertEqual(result[0], 'blocked')
        self.assertEqual(self.batches, [])

    def test_leaving_the_window_before_the_batch_is_blocked(self):
        self.world.on_link = lambda: setattr(self.clock, 'now', WED(0, 5))  # 로그인 준비하는 사이 자정을 넘겼다
        result = self.go('E-CARD-17', self.phone())
        self.assertEqual(result[0], 'blocked')
        self.assertEqual(self.batches, [])

    def test_no_notice_at_night_is_a_fail(self):
        self.scripts['daily-cards'] = lambda: self.world.give_card('id-1')
        self.assertEqual(self.go('E-CARD-17', self.phone())[0], 'fail')


class Card18Test(DeviceBase):
    def setUp(self):
        super().setUp()
        self.scripts['daily-cards'] = self.issue_to('id-1', notice=False)

    def test_card_is_made_the_switch_is_saved_on_the_server_and_nothing_arrives_in_60_seconds(self):
        result = self.go('E-CARD-18', self.phone())
        self.assertEqual(result[0], 'pass', result)
        sent = self.world.by('PATCH', '/cards/notification-settings')
        self.assertEqual([(s['body'], s['auth']) for s in sent], [({'card_arrived': False}, 'tok-1')])
        self.assertIn(('none', 60), self.windows)
        self.assertEqual(len(self.world.tables['daily_cards']), 1)

    def test_a_notice_that_arrives_anyway_is_a_fail(self):
        self.scripts['daily-cards'] = self.issue_to('id-1')
        result = self.go('E-CARD-18', self.phone())
        self.assertEqual(result[0], 'fail')

    def test_a_switch_the_server_did_not_keep_is_a_fail(self):
        self.world.handlers.insert(0, ('PATCH', re.compile(r'/cards/notification-settings'), Reply(200, {'ok': True})))  # 저장 안 하고 200
        self.assertEqual(self.go('E-CARD-18', self.phone())[0], 'fail')


class Card19Test(DeviceBase):
    def setUp(self):
        super().setUp()
        self.scripts['daily-cards'] = self.issue_to('id-1')

    def test_no_notice_while_revoked_one_notice_after_granting_again_with_the_first_card_expired(self):
        result = self.go('E-CARD-19', self.phone())
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.log, ['grant', 'revoke', 'read', 'home', 'batch:daily-cards', 'grant', 'read', 'batch:daily-cards', 'revoke'])
        self.assertEqual(len(self.world.shade), 1)  # 첫 배치 알림은 권한이 없어 안 떴고 둘째만 떴다

    def test_the_first_card_is_expired_with_a_write_that_only_touches_this_runs_owner(self):
        self.go('E-CARD-19', self.phone())
        sent = self.world.by('PATCH', '/rest/v1/daily_cards')
        self.assertEqual([s['query']['owner_id'] for s in sent], ['eq.id-1', 'eq.id-4'])  # A 와 대조군 — 대조군도 2회차 배치에서 새 카드를 받으려면 만료돼야 한다
        body = sent[0]['body']
        self.assertEqual(set(body), {'issued_at', 'expires_at'})  # 같은 날 두 번째 배치가 막히지 않게 지급 시각도 어제로
        now = datetime.now(SEOUL)
        self.assertLess(datetime.fromisoformat(body['expires_at']), now)
        self.assertLess(datetime.fromisoformat(body['issued_at']), now.replace(hour=0, minute=0, second=0, microsecond=0))

    def test_a_second_candidate_exists_so_the_first_target_resting_14_days_does_not_starve_the_second_batch(self):
        self.go('E-CARD-19', self.phone())
        self.assertEqual(len(self.world.users), 4)  # A · B · C · 대조군

    def test_a_notice_that_arrives_while_revoked_is_a_fail(self):
        self.scripts['daily-cards'] = lambda: (self.world.give_card('id-1'), self.world.post(*CARD))
        result = self.go('E-CARD-19', self.phone())
        self.assertEqual(result[0], 'fail')

    def test_a_revoke_that_did_not_take_is_blocked_so_no_notice_is_blamed_on_the_server(self):
        with mock.patch.object(notify, 'revoke_notifications', lambda serial: self.log.append('revoke')):  # granted 는 그대로 true
            result = self.go('E-CARD-19', self.phone())
        self.assertEqual(result[0], 'blocked')
        self.assertEqual(self.batches, [])

    def test_the_second_batch_without_a_new_notice_is_a_fail(self):
        self.scripts['daily-cards'] = lambda: self.world.give_card('id-1')
        self.assertEqual(self.go('E-CARD-19', self.phone())[0], 'fail')

    def test_the_permission_is_taken_away_again_even_when_the_phone_blows_up(self):
        def boom(midway=None, **job):
            raise RuntimeError('앱 죽음')

        boom.serial, boom.hub = 'S', mock.Mock()
        with self.assertRaises(RuntimeError):
            td.p_card_19(self.run, boom)
        self.assertEqual(self.log[-1], 'revoke')


class Card20Test(DeviceBase):
    SERIAL = 'emulator-5554'

    def setUp(self):
        super().setUp()
        carded = set()

        def issue():
            """활성인 사람에게만 카드를 준다 — B(id-2) 는 정지면 못 받는다. 대조군 C(id-3) 는 늘 받는다."""
            for owner in ('id-2', 'id-3'):
                if self.world.statuses.get(owner, 'active') == 'active' and owner not in carded:
                    carded.add(owner)
                    self.world.give_card(owner)
                    if owner == 'id-2' and self.granted:
                        self.world.post(*CARD)

        self.scripts['daily-cards'] = issue

    def statuses(self):
        return [s['body']['status'] for s in self.world.by('PATCH', '/rest/v1/profiles') if 'status' in s['body']]

    def test_suspended_b_gets_no_card_and_no_notice_then_active_b_gets_one_of_each(self):
        result = self.go('E-CARD-20', self.phone(serial=self.SERIAL))
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.statuses(), ['suspended', 'active'])
        self.assertEqual(self.batches, ['daily-cards', 'daily-cards'])
        self.assertEqual([c['owner_id'] for c in self.world.tables['daily_cards']], ['id-3', 'id-2'])  # 1회 대조군만, 2회 B
        self.assertEqual(len(self.world.shade), 1)

    def test_a_real_phone_is_blocked_before_any_account_is_made(self):
        phone = self.phone(serial='R58N1234')
        self.assertEqual(self.go('E-CARD-20', phone)[0], 'blocked')
        self.assertEqual((self.world.users, phone.jobs), ([], []))

    def test_a_suspended_account_that_still_gets_a_card_is_a_fail(self):
        self.scripts['daily-cards'] = lambda: [self.world.give_card(o) for o in ('id-2', 'id-3')]
        self.assertEqual(self.go('E-CARD-20', self.phone(serial=self.SERIAL))[0], 'fail')

    def test_a_suspended_account_that_still_gets_a_notice_is_a_fail(self):
        self.scripts['daily-cards'] = lambda: (self.world.give_card('id-3'), self.world.post(*CARD))
        self.assertEqual(self.go('E-CARD-20', self.phone(serial=self.SERIAL))[0], 'fail')

    def test_a_control_that_gets_no_card_means_the_batch_did_not_run_so_blocked(self):
        self.scripts['daily-cards'] = lambda: None
        result = self.go('E-CARD-20', self.phone(serial=self.SERIAL))
        self.assertEqual(result[0], 'blocked')
        self.assertEqual(self.batches, ['daily-cards'])
        self.assertEqual(self.statuses(), ['suspended', 'active'])  # 막혀도 정지는 풀어 둔다

    def test_the_suspension_is_lifted_even_when_the_batch_call_fails(self):
        def broken():
            raise Blocked('배치 호출 실패')

        self.scripts['daily-cards'] = broken
        self.assertEqual(self.go('E-CARD-20', self.phone(serial=self.SERIAL))[0], 'blocked')
        self.assertEqual(self.world.statuses['id-2'], 'active')


class Card03Test(DeviceBase):
    def setUp(self):
        super().setUp()
        self.scripts['daily-cards'] = self.issue_to('id-1', notice=False)  # 앞에 있을 때는 알림이 뜨지 않는다

    def test_app_in_front_batch_card_and_no_notice_and_the_home_key_is_never_pressed(self):
        phone = self.phone(top=OURS, midway_step={'step': 'live'})
        result = self.go('E-CARD-03', phone)
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.log, ['grant', 'read', 'batch:daily-cards', 'revoke'])  # home 없음 — 앞에 둔 채
        self.assertEqual(phone.acted, ['live'])
        self.assertIn(('none', 30), self.windows)

    def test_an_app_that_is_not_in_front_is_blocked_before_the_batch(self):
        result = self.go('E-CARD-03', self.phone(top=CHROME, midway_step={'step': 'live'}))
        self.assertEqual(result[0], 'blocked')
        self.assertEqual(self.batches, [])

    def test_a_banner_that_shows_anyway_is_a_fail(self):
        self.scripts['daily-cards'] = self.issue_to('id-1')
        self.assertEqual(self.go('E-CARD-03', self.phone(top=OURS, midway_step={'step': 'live'}))[0], 'fail')

    def test_a_card_that_never_reaches_the_db_is_blocked_because_a_slow_batch_looks_the_same(self):
        self.scripts['daily-cards'] = lambda: None
        self.assertEqual(self.go('E-CARD-03', self.phone(top=OURS, midway_step={'step': 'live'}))[0], 'blocked')

    def test_the_app_is_sent_only_the_login(self):
        phone = self.phone(top=OURS, midway_step={'step': 'live'})
        self.go('E-CARD-03', phone)
        self.assertEqual(list(phone.jobs[0]), ['token_hash'])


class Card13Test(DeviceBase):
    def setUp(self):
        super().setUp()

        def batch():
            for owner in ('id-1', 'id-3'):  # 후보가 있는 사람만 카드를 받는다
                if self.world.candidates_of(owner):
                    self.world.give_card(owner)

        self.scripts['daily-cards'] = batch

    def phone_13(self):
        return self.phone(midway_step={'step': 'batch'})

    def test_candidates_are_rested_with_expired_cards_so_the_batch_gives_a_nothing_and_the_app_sees_11b(self):
        phone = self.phone_13()
        result = self.go('E-CARD-13', phone)
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.batches, ['daily-cards'])
        self.assertEqual((self.world.live_cards('id-1'), len(self.world.live_cards('id-3'))), ([], 1))  # A 는 0장, 대조군은 1장
        rows = self.world.by('POST', '/rest/v1/daily_cards')[0]['body']
        self.assertEqual({r['owner_id'] for r in rows}, {'id-1'})  # 쓰는 것은 이번 실행 계정(A) 소유 행뿐
        self.assertEqual(len({frozenset(r) for r in rows}), 1)  # PostgREST: 행마다 키가 같아야 한다
        now = datetime.now(SEOUL)
        for row in rows:
            self.assertEqual(row['source'], 'daily')
            self.assertLess(datetime.fromisoformat(row['expires_at']), now)  # 만료됐으니 살아 있는 카드가 아니다
            self.assertGreater(datetime.fromisoformat(row['expires_at']), now - timedelta(days=14))  # 14일 쉬는 구간 안
            self.assertLess(datetime.fromisoformat(row['issued_at']), now.replace(hour=0, minute=0, second=0, microsecond=0))  # 오늘 받은 사람이 아니다

    def test_a_still_non_empty_pool_is_a_bad_preparation_so_blocked_without_the_batch(self):
        self.world.ignore_rest = True
        result = self.go('E-CARD-13', self.phone_13())
        self.assertEqual(result[0], 'blocked')
        self.assertEqual(self.batches, [])

    def test_an_owner_that_still_gets_a_live_card_is_a_fail(self):
        self.scripts['daily-cards'] = lambda: (self.world.give_card('id-1'), self.world.give_card('id-3'))
        self.assertEqual(self.go('E-CARD-13', self.phone_13())[0], 'fail')

    def test_a_control_without_a_card_means_the_batch_did_not_run_so_blocked(self):
        self.scripts['daily-cards'] = lambda: None
        self.assertEqual(self.go('E-CARD-13', self.phone_13())[0], 'blocked')

    def test_the_region_row_is_put_back_and_no_notice_machinery_is_touched(self):
        self.go('E-CARD-13', self.phone_13())
        self.assertEqual(self.region_patches()[-1], {k: ROW[k] for k in self.region_patches()[0]})
        self.assertEqual(self.log, ['batch:daily-cards'])  # 알림 권한 · 알림창은 이 가설과 상관없다


class Home29Test(DeviceBase):
    SERIAL = 'emulator-5554'
    START = WED(12)

    def setUp(self):
        super().setUp()

        def batch():
            """학교가 열렸을 때만(여는 시각 ≤ 지금) 카드 + 알림 — 닫혀 있으면 아무것도 안 준다."""
            opens = self.world.tables['universities'][0]['card_opens_at']
            if opens is None or datetime.fromisoformat(opens) <= self.clock.now:
                self.world.give_card('id-2')
                self.world.post(*CARD)

        self.scripts['daily-cards'] = batch

    def test_a_school_opened_just_before_the_batch_gives_the_first_card_and_only_the_card_notice(self):
        result = self.go('E-HOME-29', self.phone(serial=self.SERIAL))
        self.assertEqual(result[0], 'pass', result)
        opens = self.opens_patches()
        self.assertEqual(len(opens), 3)  # 닫기(미래 월요일) → 열기(지난 월요일) → 원복
        self.assertGreater(datetime.fromisoformat(opens[0]), self.clock.now)
        self.assertLess(datetime.fromisoformat(opens[1]), self.clock.now)
        self.assertIsNone(opens[2])
        self.assertEqual(self.batches, ['daily-cards'])

    def test_a_second_notice_such_as_an_opening_announcement_is_a_fail(self):
        self.scripts['daily-cards'] = lambda: (self.world.give_card('id-2'), self.world.post(*CARD), self.world.post('우리 학교가 열렸어요', '오픈'))
        self.assertEqual(self.go('E-HOME-29', self.phone(serial=self.SERIAL))[0], 'fail')

    def test_no_card_for_the_receiver_is_blocked_because_a_slow_batch_looks_the_same(self):
        self.scripts['daily-cards'] = lambda: None
        self.assertEqual(self.go('E-HOME-29', self.phone(serial=self.SERIAL))[0], 'blocked')
        self.assertIsNone(self.opens_patches()[-1])

    def test_the_school_is_put_back_even_when_the_login_was_blocked(self):
        result = self.go('E-HOME-29', self.phone(serial=self.SERIAL, push_token=False))
        self.assertEqual(result[0], 'blocked')
        self.assertIsNone(self.opens_patches()[-1])
        self.assertEqual(self.batches, [])


# ── 시계 ────────────────────────────────────────────────────────────────────────────────────────────

class OpensAtTest(DeviceBase):
    def test_the_original_is_written_to_a_file_before_the_first_patch_and_removed_after_the_restore(self):
        self.world.tables['universities'][0]['card_opens_at'] = '2026-09-28T07:00:00+09:00'
        marker = self.run.out / td.OPENS_FILE
        with td.opens_at_set(self.run, td.future_monday(self.clock.now)):
            saved = json.loads(marker.read_text(encoding='utf-8'))
            self.assertEqual(saved, {'school': 'U', 'original': '2026-09-28T07:00:00+09:00'})
        self.assertFalse(marker.exists())

    def test_the_file_is_removed_even_when_the_body_raises(self):
        with self.assertRaises(ValueError):
            with td.opens_at_set(self.run, td.future_monday(self.clock.now)):
                raise ValueError
        self.assertFalse((self.run.out / td.OPENS_FILE).exists())

    def test_a_file_left_by_a_killed_run_is_restored_first_so_the_next_original_is_not_polluted(self):
        (self.run.out / td.OPENS_FILE).write_text(json.dumps({'school': 'U', 'original': None}), encoding='utf-8')
        self.world.tables['universities'][0]['card_opens_at'] = td.future_monday(self.clock.now).isoformat()  # 앞 실행이 닫아 둔 채 죽었다
        with td.opens_at_set(self.run, td.past_monday(self.clock.now)):
            pass
        self.assertEqual(self.opens_patches(), [None, td.past_monday(self.clock.now).isoformat(), None])  # 먼저 되돌리고 → 이번 값 → 원복
        self.assertIsNone(self.world.tables['universities'][0]['card_opens_at'])

    def test_a_left_over_file_of_another_school_is_not_written_and_blocks(self):
        marker = self.run.out / td.OPENS_FILE
        marker.write_text(json.dumps({'school': 'OTHER', 'original': None}), encoding='utf-8')
        with self.assertRaises(Blocked) as raised:
            with td.opens_at_set(self.run, td.future_monday(self.clock.now)):
                pass
        self.assertIn('앞 실행이 남긴 원복 파일의 학교가 지금 시험대학과 다름 — 확인 후 파일을 지우고 다시', str(raised.exception))
        self.assertEqual(self.world.by('PATCH', '/rest/v1/universities'), [])
        self.assertTrue(marker.exists())  # 사람이 확인하기 전에는 지우지 않는다

    def test_a_restore_that_fails_keeps_the_file_so_the_next_run_can_try_again(self):
        self.world.handlers.insert(0, ('PATCH', re.compile(r'/rest/v1/universities'), Reply(500, {'message': '끊김'})))
        with self.assertRaises(Blocked):
            with td.opens_at_set(self.run, td.future_monday(self.clock.now)):
                pass
        self.assertTrue((self.run.out / td.OPENS_FILE).exists())

    def test_the_test_school_value_is_restored_even_when_the_body_raises(self):
        self.world.tables['universities'][0]['card_opens_at'] = '2026-09-28T07:00:00+09:00'
        with self.assertRaises(ValueError):
            with td.opens_at_set(self.run, td.future_monday(self.clock.now)):
                raise ValueError
        self.assertEqual(self.world.tables['universities'][0]['card_opens_at'], '2026-09-28T07:00:00+09:00')

    def test_only_the_test_university_row_is_written(self):
        with td.opens_at_set(self.run, td.future_monday(self.clock.now)):
            pass
        self.assertEqual([s['query']['id'] for s in self.world.by('PATCH', '/rest/v1/universities')], ['eq.U', 'eq.U'])

    def test_no_test_university_is_blocked_and_nothing_is_written(self):
        self.world.routes[('GET', '/rest/v1/university_email_domains')] = Reply(200, [])
        with self.assertRaises(Blocked):
            with td.opens_at_set(self.run, td.future_monday(self.clock.now)):
                pass
        self.assertEqual(self.world.by('PATCH', '/rest/v1/universities'), [])


class Home23Test(DeviceBase):
    START = WED(12)

    def test_closed_school_shows_the_wait_then_a_past_monday_and_a_restart_shows_the_hero(self):
        phone = self.phone({'result': 'pass'}, {'result': 'pass'})
        result = self.go('E-HOME-23', phone)
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(len(phone.jobs), 2)
        self.assertEqual(phone.jobs[0]['phase'], 'wait')
        self.assertIn('token_hash', phone.jobs[0])
        self.assertEqual({k: phone.jobs[1][k] for k in ('phase', 'fresh')}, {'phase': 'open', 'fresh': False})  # 세션을 유지한 채 강제 종료 → 실행
        self.assertNotIn('token_hash', phone.jobs[1])
        opens = self.opens_patches()
        for value in opens[:2]:  # universities_card_opens_monday_0700 check — 월요일 07:00 서울만 받는다
            moment = datetime.fromisoformat(value).astimezone(SEOUL)
            self.assertEqual((moment.weekday(), moment.hour, moment.minute), (0, 7, 0), value)
        self.assertGreater(datetime.fromisoformat(opens[0]), self.clock.now)
        self.assertLess(datetime.fromisoformat(opens[1]), self.clock.now)
        self.assertIsNone(opens[2])  # 원복

    def test_the_wait_screen_that_does_not_show_first_stops_before_the_value_is_moved(self):
        phone = self.phone({'result': 'blocked', 'note': '닫힌 학교인데 요약에 cohort 가 없음'})
        result = self.go('E-HOME-23', phone)
        self.assertEqual(result[0], 'blocked')
        self.assertEqual(len(phone.jobs), 1)
        self.assertEqual(len(self.opens_patches()), 2)  # 닫기 → 원복 (열기는 안 했다)
        self.assertIsNone(self.opens_patches()[-1])

    def test_a_hero_that_does_not_come_back_is_a_fail_and_the_school_is_still_restored(self):
        phone = self.phone({'result': 'pass'}, {'result': 'fail', 'note': '대기 화면 글자 남음'})
        self.assertEqual(self.go('E-HOME-23', phone)[0], 'fail')
        self.assertIsNone(self.opens_patches()[-1])


class Home26Test(DeviceBase):
    def test_the_server_says_not_open_yet_and_the_app_clock_is_told_the_open_day_at_0630_with_any_weekday(self):
        for now in (TUE(12), WED(12), MON(12), SUN(12)):
            with self.subTest(now=now):
                self.world.sent.clear()
                self.world.tables['universities'][0]['card_opens_at'] = None
                self.clock.now = now
                phone = self.phone()
                result = self.go('E-HOME-26', phone)
                self.assertEqual(result[0], 'pass', result)
                value = self.opens_patches()[0]
                moment = datetime.fromisoformat(value).astimezone(SEOUL)
                self.assertEqual((moment.weekday(), moment.hour), (0, 7))
                self.assertGreater(moment, now)  # 서버 시계로 아직 안 열렸다 — 그래서 cohort 가 온다
                self.assertEqual(phone.jobs[0]['opens_at'], value)
                self.assertIsNone(self.opens_patches()[-1])

    def test_an_app_that_shows_the_wrong_lines_is_a_fail(self):
        self.assertEqual(self.go('E-HOME-26', self.phone({'result': 'fail', 'note': '"D-day" 0개'}))[0], 'fail')


class Home24Test(DeviceBase):
    START = MON(6, 52)

    def answer(self, opened, loads=()):
        return {'result': 'pass', 'opened_ms': td.epoch_ms(opened), 'loads_ms': [td.epoch_ms(t) for t in loads]}

    def test_opened_within_two_minutes_after_0700_without_a_fast_loop_is_a_pass(self):
        phone = self.phone(self.answer(MON(7, 0, 20), [MON(7, 0, 0)]))
        result = self.go('E-HOME-24', phone)
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.opens_patches(), [MON(7, 0).isoformat(), None])  # 오늘 07:00 으로 — 아직 안 열린 값 — 그리고 원복
        job = phone.jobs[0]
        self.assertEqual(job['deadline_ms'], td.epoch_ms(MON(7, 4, 0)))
        self.assertIn('token_hash', job)

    def test_before_0700_is_a_fail(self):
        self.assertEqual(self.go('E-HOME-24', self.phone(self.answer(MON(6, 59, 40))))[0], 'fail')

    def test_after_0702_is_a_fail(self):
        self.assertEqual(self.go('E-HOME-24', self.phone(self.answer(MON(7, 2, 30))))[0], 'fail')

    def test_two_requests_less_than_a_minute_apart_are_a_fail(self):
        result = self.go('E-HOME-24', self.phone(self.answer(MON(7, 1, 10), [MON(7, 0, 0), MON(7, 0, 20)])))
        self.assertEqual(result[0], 'fail')
        self.assertIn('1분', result[1])

    def test_requests_a_minute_apart_are_fine(self):
        result = self.go('E-HOME-24', self.phone(self.answer(MON(7, 2, 0), [MON(7, 0, 0), MON(7, 1, 0)])))
        self.assertEqual(result[0], 'pass', result)

    def test_a_device_clock_ahead_of_the_pc_is_corrected_before_judging(self):
        self.skew = 40  # 기기 시계가 PC 보다 40초 빠르다 — 기기 07:00:30 = PC 06:59:50(07:00 전이라 fail)
        phone = self.phone(self.answer(MON(7, 0, 30)), serial='emulator-5554')
        self.assertEqual(self.go('E-HOME-24', phone)[0], 'fail')
        self.assertEqual(phone.jobs[0]['deadline_ms'], td.epoch_ms(MON(7, 4, 0)) + 40_000)  # 앱 마감도 기기 시계로

    def test_outside_the_monday_window_nothing_is_created(self):
        self.clock.now = TUE(6, 50)
        phone = self.phone()
        self.assertEqual(self.go('E-HOME-24', phone), ('blocked', '지금은 실행 금지 시간 — 월요일 06:50 에 다시'))
        self.assertEqual((phone.jobs, self.world.users, self.opens_patches()), ([], [], []))

    def test_preparation_so_slow_that_0700_is_near_is_blocked_not_a_false_result(self):
        self.world.on_link = lambda: setattr(self.clock, 'now', MON(6, 59, 40))
        phone = self.phone()
        result = self.go('E-HOME-24', phone)
        self.assertEqual(result[0], 'blocked')
        self.assertEqual(phone.jobs, [])
        self.assertEqual(self.opens_patches(), [])

    def test_an_app_that_never_saw_the_wait_screen_is_blocked(self):
        self.assertEqual(self.go('E-HOME-24', self.phone({'result': 'blocked', 'note': '시작부터 대기 화면이 아님'}))[0], 'blocked')
        self.assertIsNone(self.opens_patches()[-1])


class Home25Test(DeviceBase):
    START = WED(23, 50)

    def test_d_minus_5_on_a_wednesday_and_the_label_changes_within_a_minute_after_midnight(self):
        flipped = seoul(10, 8, 0, 0, 20)
        phone = self.phone({'result': 'pass', 'flipped_ms': td.epoch_ms(flipped)})
        result = self.go('E-HOME-25', phone)
        self.assertEqual(result[0], 'pass', result)
        job = phone.jobs[0]
        self.assertEqual(job['days'], 5)  # 수요일 → 다음 월요일 = 5일 뒤(시나리오 "D-5 → D-4")
        self.assertEqual(job['deadline_ms'], td.epoch_ms(seoul(10, 8, 0, 2, 30)))
        opens = datetime.fromisoformat(self.opens_patches()[0]).astimezone(SEOUL)
        self.assertEqual((opens.weekday(), opens.hour), (0, 7))
        self.assertEqual((opens.date() - self.clock.now.date()).days, 5)
        self.assertIsNone(self.opens_patches()[-1])

    def test_a_flip_before_midnight_or_after_a_minute_is_a_fail(self):
        for flipped in (seoul(10, 7, 23, 59, 30), seoul(10, 8, 0, 1, 20)):
            with self.subTest(flipped=flipped):
                phone = self.phone({'result': 'pass', 'flipped_ms': td.epoch_ms(flipped)})
                self.assertEqual(self.go('E-HOME-25', phone)[0], 'fail')

    def test_on_a_sunday_it_still_leaves_at_least_one_day_after_midnight(self):
        self.clock.now = seoul(10, 11, 23, 50)
        phone = self.phone({'result': 'pass', 'flipped_ms': td.epoch_ms(seoul(10, 12, 0, 0, 10))})
        self.go('E-HOME-25', phone)
        self.assertGreaterEqual(phone.jobs[0]['days'], 2)  # 자정 뒤에도 D-day 가 아니라 D-숫자여야 한다

    def test_outside_the_window_nothing_is_created(self):
        self.clock.now = WED(12)
        phone = self.phone()
        self.assertEqual(self.go('E-HOME-25', phone), ('blocked', '지금은 실행 금지 시간 — 23:50 에 다시'))
        self.assertEqual((phone.jobs, self.world.users), ([], []))


# ── 방해 금지 시간 2단계 ────────────────────────────────────────────────────────────────────────────

class Card44Test(DeviceBase):
    START = TUE(22, 30)

    def setUp(self):
        super().setUp()
        self.world.night = True
        self.scripts['chat-gate'] = self.world.send_pending
        self.state = self.run.out / 'card44_state.json'

    def night(self):
        phone = self.phone()
        return self.go('E-CARD-44', phone), phone

    def morning(self, now=WED(9, 20), **kw):
        self.world.night, self.clock.now = False, now
        phone = self.phone(**kw)
        return self.go('E-CARD-44', phone), phone

    def test_stage_one_defers_the_first_acceptance_then_delivers_the_second_at_once_and_ends_blocked_with_the_next_step(self):
        (result, note), phone = self.night()
        self.assertEqual((result, note), ('blocked', td.NIGHT_NOTE))
        self.assertIn('내일 08:10 뒤', note)
        self.assertIn('같은 --bundle', note)  # 상태 파일이 묶음 폴더 안이라 다른 --bundle 이면 못 찾는다
        self.assertIn('알림 권한은 아침까지 켜 둠', note)
        self.assertIn('아침 단계는 같은 묶음 다른 가설', note)
        self.assertIn('보다 먼저', note)  # 권한을 빼는 01 · 17 · 18 · 19 가 먼저 돌면 이미 뜬 알림이 지워질 수 있다(기기 미확인)
        self.assertEqual(phone.jobs, [{'token_hash': 'h-' + self.world.users[2]['email']}])  # 받는 사람 B(id-3) 가 폰
        decisions = self.world.by('POST', '/cards/')
        self.assertEqual([s['auth'] for s in decisions], ['tok-1', 'tok-2'])  # A1 → A2
        flips = self.world.by('PATCH', '/cards/notification-settings')
        self.assertEqual([(s['auth'], s['body']) for s in flips], [('tok-3', {'quiet_hours': False})])
        self.assertLess(self.world.sent.index(decisions[0]), self.world.sent.index(flips[0]))
        self.assertLess(self.world.sent.index(flips[0]), self.world.sent.index(decisions[1]))
        self.assertEqual(len(self.world.tables['pending_pushes']), 1)
        self.assertEqual(len(self.world.shade), 1)  # 두 번째(방해 금지를 끈 뒤) 수락만 밤에 뜸
        saved = json.loads(self.state.read_text(encoding='utf-8'))
        self.assertEqual(saved['night_date'], '2026-10-06')
        self.assertEqual((saved['receiver_id'], saved['title'], saved['text']), ('id-3', td.NIGHT_TITLE, '닉id-1 님이 대화를 하고 싶어 해요'))
        self.assertEqual(saved['pending_id'], self.world.tables['pending_pushes'][0]['id'])
        self.assertIn(('none', 60), self.windows)

    def test_stage_one_leaves_the_notification_permission_on_until_morning_when_it_succeeds(self):
        self.night()
        self.assertTrue(self.granted)
        self.assertEqual(self.log[0], 'grant')
        self.assertNotIn('revoke', self.log)  # 권한이 빠진 폰은 08시 예약 chat-gate 알림이 알림창에 안 뜬다

    def test_stage_one_takes_the_permission_back_when_it_fails(self):
        self.world.defer = False
        self.night()
        self.assertFalse(self.granted)
        self.assertEqual(self.log[-1], 'revoke')

    def test_stage_one_takes_the_permission_back_when_the_phone_blows_up(self):
        class Boom(AppPhone):
            def __call__(self, midway=None, **job):
                raise RuntimeError('앱 죽음')

        with self.assertRaises(RuntimeError):
            td.p_card_44(self.run, Boom(self.world))
        self.assertFalse(self.granted)

    def test_morning_after_a_scheduled_send_passes_only_because_the_night_left_the_permission_on(self):
        self.night()
        self.world.send_pending()  # 08시 예약 chat-gate — 권한이 있어야 알림창에 뜬다
        (result, note), _ = self.morning()
        self.assertEqual(result, 'pass', (result, note))
        self.assertEqual(self.batches, [])

    def test_morning_grants_first_and_always_revokes_at_the_end(self):
        self.night()
        self.log.clear()
        self.morning()
        self.assertEqual((self.log[0], self.log[-1]), ('grant', 'revoke'))
        self.assertFalse(self.granted)

    def test_a_morning_refused_by_the_clock_does_not_touch_the_permission(self):
        self.night()
        self.log.clear()
        (result, note), _ = self.morning(WED(7, 30))
        self.assertEqual(result, 'blocked')
        self.assertEqual(self.log, [])
        self.assertTrue(self.granted)  # 1단계가 켜 둔 그대로

    def test_stage_one_never_calls_a_batch_so_it_needs_no_batch_window(self):
        self.night()
        self.assertEqual(self.batches, [])

    def test_stage_one_on_a_monday_night_is_allowed_because_it_calls_no_batch(self):
        self.clock.now = MON(22, 30)
        self.assertEqual(self.night()[0][0], 'blocked')
        self.assertTrue(self.state.exists())

    def test_a_server_that_does_not_defer_at_night_is_a_fail_and_leaves_no_state(self):
        self.world.defer = False
        (result, note), _ = self.night()
        self.assertEqual(result, 'fail')
        self.assertFalse(self.state.exists())

    def test_a_missing_pending_row_is_a_fail(self):
        self.world.drop = True  # 알림도 없고 보관도 안 한 서버
        (result, note), _ = self.night()
        self.assertEqual(result, 'fail')
        self.assertIn('pending_pushes', note)

    def test_outside_the_night_window_with_no_state_nothing_is_created(self):
        self.clock.now = TUE(12)
        (result, note), phone = self.night()
        self.assertEqual((result, note), ('blocked', '지금은 실행 금지 시간 — 22:00 에 다시'))
        self.assertEqual((phone.jobs, self.world.users), ([], []))

    def test_morning_runs_the_chat_gate_when_the_row_is_still_there_and_the_text_is_the_original(self):
        self.night()
        (result, note), phone = self.morning()
        self.assertEqual(result, 'pass', (result, note))
        self.assertEqual(self.batches, ['chat-gate'])
        self.assertEqual(phone.jobs, [])  # 아침 단계는 앱을 다시 켜지 않는다 — 알림창과 DB 만 본다
        self.assertEqual(self.world.tables['pending_pushes'], [])
        self.assertEqual(json.loads(self.state.read_text(encoding='utf-8'))['done'], True)
        self.assertIn('deferred_sent', note)

    def test_when_the_scheduled_8am_job_already_sent_it_the_manual_batch_is_not_called(self):
        self.night()
        self.world.send_pending()  # 예약 chat-gate 가 08시에 이미 보냈다
        (result, note), _ = self.morning()
        self.assertEqual(result, 'pass', (result, note))
        self.assertEqual(self.batches, [])
        self.assertIn('예약', note)

    def test_morning_before_0810_is_blocked_with_the_time_and_state_stays_pending(self):
        self.night()
        (result, note), _ = self.morning(WED(7, 30))
        self.assertEqual((result, note), ('blocked', '지금은 실행 금지 시간 — 08:10 에 다시'))
        self.assertEqual(self.batches, [])
        self.assertNotIn('done', json.loads(self.state.read_text(encoding='utf-8')))

    def test_the_manual_chat_gate_goes_through_the_batch_gate_and_a_closed_minute_never_reaches_gcloud(self):
        self.night()
        self.world.night, self.clock.now = False, WED(9, 3)  # 정각 ±5분은 금지
        with mock.patch.object(area2, '_batch', ORIGINAL_BATCH), mock.patch.object(tools, 'batch') as gcloud, \
                mock.patch.object(batch_gate, 'now_seoul', lambda: WED(9, 3)):
            result = self.go('E-CARD-44', self.phone())
        self.assertEqual(result[0], 'blocked')
        self.assertIn('지금은 실행 금지 시간', result[1])
        gcloud.assert_not_called()
        self.assertEqual(len(self.world.tables['pending_pushes']), 1)

    def test_the_manual_chat_gate_in_an_open_minute_reaches_gcloud_once(self):
        self.night()
        self.world.night, self.clock.now = False, WED(9, 20)
        history = Path(tempfile.mkdtemp()) / 'runs.jsonl'
        with mock.patch.object(area2, '_batch', ORIGINAL_BATCH), mock.patch.object(tools, 'batch', lambda name: self.batch(name)), \
                mock.patch.object(batch_gate, 'now_seoul', lambda: WED(9, 20)), mock.patch.object(batch_gate, 'HISTORY', history):
            result = self.go('E-CARD-44', self.phone())
        self.assertEqual(result[0], 'pass', result)
        self.assertEqual(self.batches, ['chat-gate'])

    def test_a_row_that_vanished_but_no_notice_in_the_shade_is_a_fail(self):
        self.night()
        self.world.tables['pending_pushes'] = []  # 행은 지워졌는데 알림이 안 보인다
        self.world.shade.clear()
        (result, note), _ = self.morning()
        self.assertEqual(result, 'fail')
        self.assertIn('알림', note)

    def test_a_different_text_is_a_fail(self):
        self.night()
        self.scripts['chat-gate'] = lambda: (self.world.tables.__setitem__('pending_pushes', []),
                                              self.world.post(td.NIGHT_TITLE, '밤사이 2명이 나를 수락했어요'))
        self.assertEqual(self.morning()[0][0], 'fail')

    def test_a_state_two_days_old_starts_over_instead_of_judging_a_notice_that_may_be_gone(self):
        self.night()
        self.world.night, self.clock.now = False, seoul(10, 8, 9, 20)
        result = self.go('E-CARD-44', self.phone())
        self.assertEqual(result, ('blocked', '지금은 실행 금지 시간 — 22:00 에 다시'))

    def test_after_a_finished_morning_the_next_night_starts_stage_one_again(self):
        self.night()
        self.morning()
        self.world.night, self.clock.now = True, WED(22, 30)
        (result, note), _ = self.night()
        self.assertEqual(result, 'blocked')
        self.assertIn('1단계', note)
        self.assertEqual(json.loads(self.state.read_text(encoding='utf-8'))['night_date'], '2026-10-07')

    def test_the_receiver_must_be_an_account_this_run_made(self):
        self.night()
        saved = json.loads(self.state.read_text(encoding='utf-8'))
        saved['receiver_id'] = 'someone-elses-id'
        self.state.write_text(json.dumps(saved), encoding='utf-8')
        (result, note), _ = self.morning()
        self.assertEqual(result, 'blocked')
        self.assertEqual(self.batches, [])


# ── 등록 · 안전망 ───────────────────────────────────────────────────────────────────────────────────

CASES = ['E-CARD-01', 'E-CARD-03', 'E-CARD-13', 'E-CARD-17', 'E-CARD-18', 'E-CARD-19', 'E-CARD-20', 'E-HOME-29',
         'E-HOME-23', 'E-HOME-24', 'E-HOME-25', 'E-HOME-26', 'E-CARD-44']
A_PHONE = ['E-CARD-01', 'E-CARD-03', 'E-CARD-13', 'E-CARD-17', 'E-CARD-18', 'E-CARD-19', 'E-CARD-44']
B_EMULATOR = ['E-CARD-20', 'E-HOME-23', 'E-HOME-24', 'E-HOME-25', 'E-HOME-26', 'E-HOME-29']
APP_KEYS = ['phase', 'days', 'deadline_ms', 'opens_at']  # PC 가 앱 일감에 싣는 키 중 area2_d.dart 가 읽는 것
INSIDE = {'E-CARD-17': TUE(22, 30), 'E-CARD-44': TUE(22, 30), 'E-HOME-24': MON(6, 52), 'E-HOME-25': WED(23, 50)}  # 시각 창이 있는 가설


class RegistryTest(unittest.TestCase):
    def dart(self, name):
        return (tools.ROOT / 'frontend' / 'integration_test' / name).read_text(encoding='utf-8')

    def test_the_bundles_are_the_13_split_by_device_and_every_case_is_a_phone_case(self):
        self.assertEqual(sorted(area1.BUNDLES['area2-time-device']), sorted(CASES))
        self.assertEqual(len(CASES), 13)
        self.assertEqual(sorted(area1.BUNDLES['area2-time-device-a']), sorted(A_PHONE))
        self.assertEqual(sorted(area1.BUNDLES['area2-time-device-b']), sorted(B_EMULATOR))
        self.assertEqual(sorted(A_PHONE + B_EMULATOR), sorted(CASES))
        for case in CASES:
            self.assertIs(area1.PHONE[case], td.PHONE[case], case)

    def test_main_registers_the_module_and_none_is_an_api_case(self):
        from e2e import __main__ as main
        self.assertIn('from e2e import area2_time_device', Path(main.__file__).read_text(encoding='utf-8'))  # 이 시험 파일이 먼저 불러도 main 이 스스로 불러야 한다
        self.assertEqual(sorted(main.BUNDLES['area2-time-device']), sorted(CASES))
        self.assertFalse(set(CASES) & set(main.API_CASES))

    def test_the_app_has_every_number_and_reads_every_key_the_pc_sends(self):
        dart = self.dart('area2_d.dart')
        for case in CASES:
            self.assertRegex(dart, rf"(?m)^  '{case}':", case)
        for key in APP_KEYS:
            self.assertIn(f"job['{key}']", dart, key)

    def test_e2e_test_merges_the_app_cases(self):
        main = self.dart('e2e_test.dart')
        self.assertIn("import 'area2_d.dart';", main)
        self.assertIn('...area2dCases', main)

    def test_the_replaced_app_is_wrapped_like_main_with_the_session_scope(self):
        dart = self.dart('area2_d.dart')
        self.assertIn('SessionScope(', dart)
        self.assertIn('authChanges: Supabase.instance.client.auth.onAuthStateChange', dart)
        self.assertLess(dart.index('SessionScope('), dart.index('homeNowProvider.overrideWithValue'))  # 세션 범위 안쪽에 시계 override

    def test_the_app_only_overrides_the_clock_slot_and_changes_no_lib_code(self):
        dart = self.dart('area2_d.dart')
        self.assertIn('homeNowProvider.overrideWithValue', dart)  # E-HOME-26 — 시계 자리 방식(lib/ 변경 0)


class SafetyNetTest(DeviceBase):
    def test_every_case_ends_blocked_or_fail_when_the_server_is_down(self):
        down = World()
        for method in ('GET', 'POST', 'PATCH', 'DELETE'):
            down.on(method, r'.*', Reply(500, {'detail': '서버'}))
        with mock.patch.object(tools, 'call', down):
            for case in CASES:
                self.clock.now = INSIDE.get(case, TUE(12))
                result = area1.attempt_phone(self.run, case, AppPhone(down, serial='emulator-5554'))
                self.assertIn(result[0], ('blocked', 'fail'), case)
                self.assertIsInstance(result[1], str, case)

    def test_every_write_in_every_case_stays_inside_this_runs_accounts_the_test_school_and_the_test_region(self):
        allowed = {'region_group_settings': ('region_group', 'e2e'), 'universities': ('id', 'U')}
        for case in CASES:
            world = World()
            self.reset()
            self.world = world
            self.clock.now = INSIDE.get(case, TUE(12))
            self.scripts['daily-cards'] = self.issue_to('id-1', 'id-2', 'id-3')
            with mock.patch.object(tools, 'call', world):
                self.go(case, AppPhone(world, serial='emulator-5554', top=OURS, midway_step={'step': 'x'}))
            made = {u['id'] for u in world.users}
            self.assertTrue(made, case)
            for sent in world.sent:
                if sent['method'] not in ('POST', 'PATCH', 'DELETE') or not sent['path'].startswith('/rest/v1/'):
                    continue
                table = sent['path'].split('/')[-1]
                if table in allowed:
                    key, value = allowed[table]
                    self.assertEqual(sent['query'].get(key), f'eq.{value}', (case, sent))
                elif table in ('daily_cards', 'profiles', 'pending_pushes', 'push_tokens'):
                    rows = sent['body'] if isinstance(sent['body'], list) else [sent['body']]
                    owners = {r['owner_id'] for r in rows if isinstance(r, dict) and 'owner_id' in r}
                    owners |= {sent['query'][k][3:] for k in ('owner_id', 'id', 'profile_id') if k in sent['query']}
                    self.assertTrue(owners and owners <= made, (case, sent))


if __name__ == '__main__':
    unittest.main()
