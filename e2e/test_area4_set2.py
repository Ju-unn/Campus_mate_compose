"""영역 4 설정(SET) 2차 PC 쪽 시험 — FAQ · 친구 초대 · 하트 모으기 · 로그아웃 · 탈퇴. 폰 · 운영 없이 가짜 앱 · 가짜 DB.
저장소 루트에서 `python -m unittest e2e.test_area4_set2`."""

import subprocess
import unittest
from unittest import mock

from e2e import area1, area4, area4_set2, notify, tools
from e2e.test_area1 import Base
from e2e.test_area4 import FakeDb
from e2e.test_area1_phone import APP_PASS, FakePhone
from e2e.tools import Blocked

FAQ = [
    {'category': 'card_matching', 'question': '카드는 언제 와요?', 'answer': '아침 7시에 와요.', 'sort_order': 1},
    {'category': 'card_matching', 'question': '하트가 뭐예요?', 'answer': '재화예요.', 'sort_order': 2},
    {'category': 'heart_payment', 'question': '하트는 어떻게 모아요?', 'answer': '과제를 하면 돼요. Free 로 모아요.', 'sort_order': 1},
    {'category': 'heart_payment', 'question': '환불해 주나요?', 'answer': '결제 후 7일 안에요.', 'sort_order': 2},
    {'category': 'photo_profile', 'question': '사진을 바꿀 수 있나요?', 'answer': '네.', 'sort_order': 1},
    {'category': 'friend_review', 'question': '리뷰는 누가 써요?', 'answer': '지인이요.', 'sort_order': 1},
    {'category': 'safety', 'question': '신고하면 어떻게 돼요?', 'answer': '확인해요.', 'sort_order': 1},
    {'category': 'account', 'question': '탈퇴하면요?', 'answer': '삭제돼요.', 'sort_order': 1},
    {'category': 'account', 'question': '로그아웃은요?', 'answer': '시트가 떠요.', 'sort_order': 2},
]


class Db(FakeDb):
    """FakeDb + faq · push_tokens 표 + 한 칸만 읽는 profiles 조회."""

    def __init__(self):
        super().__init__()
        self.faq = [dict(r) for r in FAQ]
        self.tokens = []
        self.fields = {'referral_code': 'K7M2QX', 'nickname': 'Aaaaa', 'status': 'active', 'matching_paused': False}

    def __call__(self, method, url, headers=None, body=None, raw=None):
        from urllib.parse import parse_qs, urlsplit
        parts = urlsplit(url)
        if parts.path == '/rest/v1/faq' and method == 'GET':
            self.calls.append((method, parts.path, body))
            return tools.Reply(200, self.faq)
        if parts.path == '/rest/v1/push_tokens' and method == 'GET':
            self.calls.append((method, parts.path, body))
            return tools.Reply(200, list(self.tokens))
        select = parse_qs(parts.query).get('select', [''])[0]
        if parts.path == '/rest/v1/profiles' and method == 'GET' and select in self.fields:
            self.calls.append((method, parts.path, body))
            return tools.Reply(200, [{select: self.fields[select]}])
        return super().__call__(method, url, headers, body, raw)


def serve(case):
    patcher = mock.patch.object(tools, 'call', db := Db())
    patcher.start()
    case.addCleanup(patcher.stop)
    return db


class ExpectedTest(unittest.TestCase):
    def test_tabs_keep_the_enum_order_and_questions_keep_sort_order(self):
        by = area4_set2.by_category(FAQ)
        self.assertEqual(list(by), ['card_matching', 'heart_payment', 'photo_profile', 'friend_review', 'safety', 'account'])
        self.assertEqual(by['account'], ['탈퇴하면요?', '로그아웃은요?'])

    def test_search_matches_question_or_answer_after_trim_and_lowercase_in_tab_then_sort_order(self):
        self.assertEqual(area4_set2.hits(FAQ, '  하트  '), ['하트가 뭐예요?', '하트는 어떻게 모아요?'])
        self.assertEqual(area4_set2.hits(FAQ, 'FREE'), ['하트는 어떻게 모아요?'])  # 답변에서도
        self.assertEqual(area4_set2.hits(FAQ, 'ㅋㅋㅋzzqq'), [])

    def test_english_word_is_found_in_question_or_answer(self):
        self.assertEqual(area4_set2.english_word(FAQ), 'Free')
        self.assertIsNone(area4_set2.english_word([{'question': '가', 'answer': '나'}]))

    def test_headers_are_the_labels_of_the_tabs_that_have_a_hit(self):
        self.assertEqual(area4_set2.header_labels(FAQ, '하트'), ['카드·매칭', '하트·결제'])


class RegistryTest(unittest.TestCase):
    def test_every_set_number_has_exactly_one_home(self):
        set1, set2 = set(area1.BUNDLES['area4-set1']), set(area1.BUNDLES['area4-set2'])
        homes = {}
        for number in range(1, 71):
            case = f'E-SET-{number:02d}'
            where = [name for name, group in (('set1', set1), ('set2', set2), ('left', set(area4.LEFT_OUT)),
                                              ('emulator', set(area4.EMULATOR))) if case in group]
            homes[case] = where
        bad = {case: where for case, where in homes.items() if len(where) != 1}
        self.assertEqual(bad, {})

    def test_set_two_is_the_planned_twenty_three(self):
        plan = [2, 3, *range(44, 52), 54, *range(58, 67), 68, 69, 70]
        plan = [n for n in plan if n != 52]
        self.assertEqual(sorted(area1.BUNDLES['area4-set2']), sorted(f'E-SET-{n:02d}' for n in plan))
        self.assertEqual(len(area1.BUNDLES['area4-set2']), 23)
        for case in area1.BUNDLES['area4-set2']:
            self.assertIn(case, area1.PHONE)

    def test_mail_app_case_is_left_out_because_it_would_leave_a_draft_in_a_real_mailbox(self):
        self.assertIn('임시', area4.LEFT_OUT['E-SET-52'])


class NotifyHelpersTest(unittest.TestCase):
    def test_grant_notifications_grants_only_our_app_the_post_permission(self):
        calls = []
        with mock.patch.object(tools, 'adb', lambda s, *a, check=True: calls.append(a) or ''):
            notify.grant_notifications('S')
        self.assertEqual(calls, [('shell', 'pm', 'grant', tools.PACKAGE, 'android.permission.POST_NOTIFICATIONS')])

    def test_screen_has_reads_the_ui_dump_as_utf8_bytes_and_never_returns_it(self):
        dump = '<hierarchy><node text="CampusMate 에서 같이 해요! 가입할 때 추천 코드 K7M2QX 를 넣어 줘." /></hierarchy>'
        done = subprocess.CompletedProcess([], 0, stdout=dump.encode('utf-8'), stderr=b'')
        with mock.patch.object(notify.subprocess, 'run', return_value=done) as run:
            self.assertIs(notify.screen_has('S', '추천 코드 K7M2QX'), True)
            self.assertIs(notify.screen_has('S', '없는 글'), False)
        self.assertEqual(run.call_args.args[0], ['adb', '-s', 'S', 'shell', 'uiautomator', 'dump', '/dev/tty'])
        self.assertNotIn('text', run.call_args.kwargs)  # 글자 해석은 우리가 한다 — 로케일에 맡기지 않는다

    def test_screen_has_survives_bytes_that_are_not_utf8(self):
        done = subprocess.CompletedProcess([], 0, stdout=b'\xff\xfe \xea\xb0\x80', stderr=b'')
        with mock.patch.object(notify.subprocess, 'run', return_value=done):
            self.assertIs(notify.screen_has('S', '가'), True)

    def test_grant_failure_is_blocked_not_a_crash(self):
        error = subprocess.CalledProcessError(255, 'adb')
        with mock.patch.object(tools, 'adb', side_effect=error):
            with self.assertRaises(Blocked):
                notify.grant_notifications('S')

    def test_revoke_notifications_takes_the_permission_back_and_never_raises(self):
        calls = []
        with mock.patch.object(tools, 'adb', lambda s, *a, check=True: calls.append((a, check)) or ''):
            notify.revoke_notifications('S')
        self.assertEqual(calls, [(('shell', 'pm', 'revoke', tools.PACKAGE, 'android.permission.POST_NOTIFICATIONS'), False)])


class FaqCaseTest(Base):
    def attempt(self, case, answer=APP_PASS):
        db = serve(self)
        sent = []

        def app(midway=None, **job):
            sent.append(job)
            if midway:
                midway({'step': 'x'})
            return answer

        app.serial = 'S'
        app.hub = mock.Mock(wait=mock.Mock(return_value={'step': 'next'}))
        with mock.patch.object(area4_set2.notify, 'airplane') as plane, mock.patch.object(area4_set2.notify, 'ensure_online') as online:
            result = area1.attempt_phone(self.run, case, app)
        return result, sent, db, plane, online

    def test_set_44_first_tab_questions_come_from_the_db(self):
        (result, _), sent, _, _, _ = self.attempt('E-SET-44')
        self.assertEqual(result, 'pass')
        self.assertEqual(sent[0]['questions'], ['카드는 언제 와요?', '하트가 뭐예요?'])
        self.assertEqual(sent[0]['labels'], ['카드·매칭', '하트·결제', '사진·프로필', '지인 리뷰', '안전·신고', '계정'])

    def test_set_45_every_tab_gets_its_own_question_list(self):
        (result, _), sent, _, _, _ = self.attempt('E-SET-45')
        self.assertEqual(result, 'pass')
        self.assertEqual(sent[0]['expected']['계정'], ['탈퇴하면요?', '로그아웃은요?'])
        self.assertEqual([len(v) for v in sent[0]['expected'].values()], [2, 2, 1, 1, 1, 2])

    def test_set_46_needs_two_questions_and_both_answers(self):
        (result, _), sent, _, _, _ = self.attempt('E-SET-46')
        self.assertEqual(result, 'pass')
        self.assertEqual(sent[0]['questions'], ['카드는 언제 와요?', '하트가 뭐예요?'])
        self.assertEqual(sent[0]['answers'], ['아침 7시에 와요.', '재화예요.'])

    def test_set_46_is_blocked_when_the_first_tab_has_one_question_only(self):
        db = serve(self)
        db.faq = [r for r in db.faq if r['question'] != '하트가 뭐예요?']
        phone = FakePhone()
        phone.serial = 'S'
        self.assertEqual(area1.attempt_phone(self.run, 'E-SET-46', phone)[0], 'blocked')

    def test_set_47_collapses_on_tab_change(self):
        (result, _), sent, _, _, _ = self.attempt('E-SET-47')
        self.assertEqual(result, 'pass')
        self.assertEqual((sent[0]['question'], sent[0]['answer'], sent[0]['other_tab']),
                         ('카드는 언제 와요?', '아침 7시에 와요.', '하트·결제'))

    def test_set_48_search_expects_the_hit_questions_and_headers(self):
        (result, _), sent, _, _, _ = self.attempt('E-SET-48')
        self.assertEqual(result, 'pass')
        self.assertEqual((sent[0]['needle'], sent[0]['expected'], sent[0]['headers']),
                         ('하트', ['하트가 뭐예요?', '하트는 어떻게 모아요?'], ['카드·매칭', '하트·결제']))

    def test_set_48_is_blocked_when_nothing_contains_the_word(self):
        db = serve(self)
        db.faq = [r for r in db.faq if '하트' not in r['question'] + r['answer']]
        phone = FakePhone()
        phone.serial = 'S'
        self.assertEqual(area1.attempt_phone(self.run, 'E-SET-48', phone)[0], 'blocked')

    def test_set_49_variants_must_give_the_same_list_as_the_plain_word(self):
        (result, _), sent, _, _, _ = self.attempt('E-SET-49')
        self.assertEqual(result, 'pass')
        variants = {v['text']: v['expected'] for v in sent[0]['variants']}
        self.assertEqual(variants['  하트  '], ['하트가 뭐예요?', '하트는 어떻게 모아요?'])
        self.assertEqual(variants['free'], variants['FREE'])
        self.assertEqual(variants['fREE'], ['하트는 어떻게 모아요?'])

    def test_set_49_is_blocked_without_any_english_word(self):
        db = serve(self)
        db.faq = [{**r, 'answer': r['answer'].replace('Free', '프리')} for r in db.faq]
        phone = FakePhone()
        phone.serial = 'S'
        self.assertEqual(area1.attempt_phone(self.run, 'E-SET-49', phone)[0], 'blocked')

    def test_set_50_blank_search_keeps_the_first_tab(self):
        (result, _), sent, _, _, _ = self.attempt('E-SET-50')
        self.assertEqual(result, 'pass')
        self.assertEqual(sent[0]['questions'], ['카드는 언제 와요?', '하트가 뭐예요?'])

    def test_set_51_word_must_not_match_anything(self):
        (result, _), sent, _, _, _ = self.attempt('E-SET-51')
        self.assertEqual((result, sent[0]['needle']), ('pass', 'ㅋㅋㅋzzqq'))

    def test_set_54_searches_inside_the_account_tab_then_clear_returns_to_it(self):
        (result, _), sent, _, _, _ = self.attempt('E-SET-54')
        self.assertEqual(result, 'pass')
        self.assertEqual((sent[0]['tab'], sent[0]['after_clear']), ('계정', ['탈퇴하면요?', '로그아웃은요?']))
        self.assertTrue(area4_set2.hits(FAQ, sent[0]['needle']))

    def test_set_02_cuts_the_network_after_login_and_always_goes_online_again(self):
        (result, _), sent, _, plane, online = self.attempt('E-SET-02')
        self.assertEqual(result, 'pass')
        self.assertEqual([c.args[1] for c in plane.call_args_list], [True])
        online.assert_called_once_with('S')

    def test_set_03_caches_in_the_first_launch_then_goes_offline_in_the_second(self):
        (result, _), sent, _, plane, online = self.attempt('E-SET-03')
        self.assertEqual(result, 'pass')
        self.assertEqual([j.get('phase') for j in sent], ['cache', 'offline'])
        self.assertEqual(sent[1]['fresh'], False)
        self.assertEqual(sent[1]['questions'], ['카드는 언제 와요?', '하트가 뭐예요?'])
        online.assert_called_once_with('S')


class InviteCaseTest(Base):
    def attempt(self, case, **fields):
        db = serve(self)
        db.fields.update(fields)
        sent = []

        def app(midway=None, **job):
            sent.append(job)
            if midway:
                midway({'step': 'x'})
            return APP_PASS

        app.serial = 'S'
        app.hub = mock.Mock(wait=mock.Mock(return_value={'step': 'next'}))
        app.top = lambda: 'topResumedActivity=ActivityRecord{1 u0 android/com.android.internal.app.ChooserActivity t9}'
        with mock.patch.object(area4_set2.notify, 'airplane') as plane, mock.patch.object(area4_set2.notify, 'ensure_online') as online, \
                mock.patch.object(area4_set2.notify, 'screen_has', return_value=True) as seen, \
                mock.patch.object(area4_set2.time, 'sleep'), mock.patch.object(tools, 'adb', return_value=''):
            result = area1.attempt_phone(self.run, case, app)
        return result, sent, db, plane, online, seen

    def test_58_59_62_hand_the_db_code_to_the_app(self):
        for case in ('E-SET-58', 'E-SET-59', 'E-SET-62'):
            with self.subTest(case):
                (result, _), sent, *_ = self.attempt(case)
                self.assertEqual((result, sent[0]['code']), ('pass', 'K7M2QX'), case)

    def test_58_is_blocked_without_a_referral_code(self):
        (result, note), *_ = self.attempt('E-SET-58', referral_code=None)
        self.assertEqual(result, 'blocked')

    def test_60_share_sheet_must_be_in_front_show_the_text_then_back_is_pressed(self):
        db = serve(self)
        sent, adb_calls = [], []

        def app(midway=None, **job):
            sent.append(job)
            midway({'step': 'shared'})
            return APP_PASS

        app.serial = 'S'
        app.top = lambda: 'topResumedActivity=ActivityRecord{1 u0 android/com.android.internal.app.ChooserActivity t9}'
        with mock.patch.object(area4_set2.notify, 'screen_has', return_value=True) as seen, \
                mock.patch.object(area4_set2.time, 'sleep'), \
                mock.patch.object(tools, 'adb', lambda s, *a, check=True: adb_calls.append(a) or ''):
            self.assertEqual(area1.attempt_phone(self.run, 'E-SET-60', app)[0], 'pass')
        seen.assert_called_once_with('S', 'CampusMate 에서 같이 해요! 가입할 때 추천 코드 K7M2QX 를 넣어 줘.')
        self.assertIn(('shell', 'input', 'keyevent', 'KEYCODE_BACK'), adb_calls)

    def test_60_fails_when_our_app_is_still_in_front(self):
        db = serve(self)

        def app(midway=None, **job):
            midway({'step': 'shared'})
            return APP_PASS

        app.serial = 'S'
        app.top = lambda: 'topResumedActivity=ActivityRecord{1 u0 io.github.juunn.campusmate/.MainActivity t9}'
        with mock.patch.object(area4_set2.notify, 'screen_has', return_value=True), \
                mock.patch.object(area4_set2.time, 'sleep'), mock.patch.object(tools, 'adb', return_value=''):
            result, note = area1.attempt_phone(self.run, 'E-SET-60', app)
        self.assertEqual(result, 'fail')
        self.assertIn('공유 창', note)

    def run60(self, top, text_seen):
        db = serve(self)

        def app(midway=None, **job):
            midway({'step': 'shared'})
            return APP_PASS

        app.serial = 'S'
        app.top = lambda: top
        with mock.patch.object(area4_set2.notify, 'screen_has', return_value=text_seen),                 mock.patch.object(area4_set2.time, 'sleep'), mock.patch.object(tools, 'adb', return_value=''):
            return area1.attempt_phone(self.run, 'E-SET-60', app)

    def test_60_passes_with_a_note_when_the_sheet_is_up_but_the_phone_hides_the_preview(self):
        result, note = self.run60('topResumedActivity=ActivityRecord{1 u0 android/com.android.internal.app.ChooserActivity t9}', False)
        self.assertEqual(result, 'pass')
        self.assertIn('미리보기', note)

    def test_60_also_accepts_the_resolver_sheet(self):
        result, note = self.run60('topResumedActivity=ActivityRecord{1 u0 android/com.android.internal.app.ResolverActivity t9}', False)
        self.assertEqual(result, 'pass')

    def test_60_fails_when_something_else_than_a_share_sheet_is_in_front_and_no_text(self):
        result, note = self.run60('topResumedActivity=ActivityRecord{1 u0 com.android.settings/.Settings t9}', False)
        self.assertEqual(result, 'fail')
        self.assertIn('글', note)

    def test_61_cuts_then_restores(self):
        (result, _), sent, db, plane, online, _ = self.attempt('E-SET-61')
        self.assertEqual(result, 'pass')
        self.assertEqual([c.args[1] for c in plane.call_args_list], [True, False])
        online.assert_called_once_with('S')


class AccountCaseTest(Base):
    def attempt(self, case, action=None, **fields):
        db = serve(self)
        db.fields.update(fields)
        sent = []

        def app(midway=None, **job):
            sent.append(job)
            if midway:
                midway({'step': 'ready'})
            if action:
                action(db, job)
            return APP_PASS

        app.serial = 'S'
        app.hub = mock.Mock(wait=mock.Mock(return_value={'step': 'next'}))
        with mock.patch.object(area4_set2.notify, 'airplane') as plane, mock.patch.object(area4_set2.notify, 'ensure_online') as online, \
                mock.patch.object(area4_set2.notify, 'grant_notifications') as grant, \
                mock.patch.object(area4_set2.time, 'sleep'), mock.patch.object(tools, 'adb', return_value=''):
            result = area1.attempt_phone(self.run, case, app)
        return result, sent, db, plane, online, grant

    def test_63_64_just_start_the_app_on_a_home_account(self):
        for case in ('E-SET-63', 'E-SET-64'):
            with self.subTest(case):
                (result, _), sent, *_ = self.attempt(case)
                self.assertEqual((result, 'token_hash' in sent[0]), ('pass', True), case)

    def test_65_waits_for_the_device_token_then_the_row_must_be_gone_after_logout(self):
        def logout(db, job):
            db.tokens.clear()

        def token_arrives(db, job):
            pass

        db = serve(self)
        db.tokens = [{'token': 'T', 'profile_id': 'id-1'}]
        sent = []

        def app(midway=None, **job):
            sent.append(job)
            midway({'step': 'ready'})
            db.tokens.clear()  # 앱이 로그아웃 → 서버가 토큰 행을 지움
            return APP_PASS

        app.serial = 'S'
        app.hub = mock.Mock()
        with mock.patch.object(area4_set2.notify, 'grant_notifications') as grant, \
                mock.patch.object(area4_set2.notify, 'revoke_notifications') as revoke, \
                mock.patch.object(area4_set2.time, 'sleep'):
            self.assertEqual(area1.attempt_phone(self.run, 'E-SET-65', app)[0], 'pass')
        grant.assert_called_once_with('S')
        revoke.assert_called_once_with('S')

    def test_65_gives_the_permission_back_even_when_it_ends_blocked(self):
        db = serve(self)

        def app(midway=None, **job):
            midway({'step': 'ready'})
            return APP_PASS

        app.serial = 'S'
        app.hub = mock.Mock()
        with mock.patch.object(area4_set2.notify, 'grant_notifications'), \
                mock.patch.object(area4_set2.notify, 'revoke_notifications') as revoke, \
                mock.patch.object(area4_set2.time, 'sleep'), \
                mock.patch.object(area4_set2.time, 'monotonic', side_effect=[0, 1, 31, 32, 33]):
            self.assertEqual(area1.attempt_phone(self.run, 'E-SET-65', app)[0], 'blocked')
        revoke.assert_called_once_with('S')

    def test_65_is_blocked_when_no_token_ever_arrives(self):
        db = serve(self)

        def app(midway=None, **job):
            midway({'step': 'ready'})
            return APP_PASS

        app.serial = 'S'
        app.hub = mock.Mock()
        with mock.patch.object(area4_set2.notify, 'grant_notifications'), mock.patch.object(area4_set2.notify, 'revoke_notifications'), \
                mock.patch.object(area4_set2.time, 'sleep'), \
                mock.patch.object(area4_set2.time, 'monotonic', side_effect=[0, 1, 31, 32, 33]):
            self.assertEqual(area1.attempt_phone(self.run, 'E-SET-65', app)[0], 'blocked')

    def test_65_fails_when_the_row_stays_after_logout(self):
        db = serve(self)
        db.tokens = [{'token': 'T', 'profile_id': 'id-1'}]

        def app(midway=None, **job):
            midway({'step': 'ready'})
            return APP_PASS

        app.serial = 'S'
        app.hub = mock.Mock()
        ticks = iter(range(0, 1000))
        with mock.patch.object(area4_set2.notify, 'grant_notifications'), mock.patch.object(area4_set2.notify, 'revoke_notifications'), \
                mock.patch.object(area4_set2.time, 'sleep'), \
                mock.patch.object(area4_set2.time, 'monotonic', side_effect=lambda: next(ticks)):
            result, note = area1.attempt_phone(self.run, 'E-SET-65', app)
        self.assertEqual(result, 'fail')
        self.assertIn('push_tokens', note)

    def test_66_hands_over_the_first_nickname_and_a_second_login(self):
        (result, _), sent, *_ = self.attempt('E-SET-66', nickname='Zxcvb')
        self.assertEqual(result, 'pass')
        self.assertEqual(sent[0]['nick'], 'Zxcvb')
        self.assertIn('second', sent[0])

    def test_68_cuts_before_logout_and_goes_online_after(self):
        (result, _), sent, db, plane, online, _ = self.attempt('E-SET-68')
        self.assertEqual(result, 'pass')
        self.assertEqual([c.args[1] for c in plane.call_args_list], [True])
        online.assert_called_once_with('S')

    def test_69_pausing_keeps_the_account_active_and_pauses_matching(self):
        def pause(db, job):
            db.fields['matching_paused'] = True

        (result, _), *_ = self.attempt('E-SET-69', pause)
        self.assertEqual(result, 'pass')

    def test_69_waits_for_the_server_to_save_the_pause(self):
        db = serve(self)
        reads = iter([False, False, True, True, 'active'])  # 기다림 3번(앞 둘은 아직) → 확인 1번 → 상태 1번

        def app(midway=None, **job):
            return APP_PASS

        app.serial = 'S'
        with mock.patch.object(area4_set2, '_profile_value', side_effect=lambda *a: next(reads)), \
                mock.patch.object(area4_set2.time, 'sleep'):
            self.assertEqual(area1.attempt_phone(self.run, 'E-SET-69', app)[0], 'pass')

    def test_69_fails_when_matching_was_not_paused(self):
        ticks = iter(range(0, 1000))
        with mock.patch.object(area4_set2.time, 'monotonic', side_effect=lambda: next(ticks)):
            (result, note), *_ = self.attempt('E-SET-69')
        self.assertEqual(result, 'fail')
        self.assertIn('matching_paused', note)

    def test_69_fails_when_the_account_got_withdrawn(self):
        def wrong(db, job):
            db.fields.update(matching_paused=True, status='withdrawn')

        (result, note), *_ = self.attempt('E-SET-69', wrong)
        self.assertEqual(result, 'fail')
        self.assertIn('status', note)

    def run70(self, status='withdrawn', tokens_after=False, tokens_before=True, ticks=None):
        db = serve(self)
        db.tokens = [{'token': 'T', 'profile_id': 'id-1'}] if tokens_before else []

        def app(midway=None, **job):
            midway({'step': 'ready'})
            db.fields['status'] = status
            db.tokens = [{'token': 'T', 'profile_id': 'id-1'}] if tokens_after else []
            return APP_PASS

        app.serial = 'S'
        app.hub = mock.Mock()
        patches = [mock.patch.object(area4_set2.notify, 'grant_notifications'),
                   mock.patch.object(area4_set2.notify, 'revoke_notifications'),
                   mock.patch.object(area4_set2.time, 'sleep')]
        if ticks:
            patches.append(mock.patch.object(area4_set2.time, 'monotonic', side_effect=lambda: next(ticks)))
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)
        return area1.attempt_phone(self.run, 'E-SET-70', app)

    def test_70_withdrawn_status_and_the_token_that_was_there_is_gone(self):
        self.assertEqual(self.run70()[0], 'pass')

    def test_70_is_blocked_when_there_was_never_a_token_to_remove(self):
        result = self.run70(tokens_before=False, ticks=iter([0, 1, 31, 32, 33]))
        self.assertEqual(result[0], 'blocked')

    def test_70_fails_when_the_status_is_still_active(self):
        result, note = self.run70(status='active')
        self.assertEqual(result, 'fail')
        self.assertIn('withdrawn', note)

    def test_70_fails_when_a_device_token_is_left(self):
        result, note = self.run70(tokens_after=True, ticks=iter(range(0, 1000)))
        self.assertEqual(result, 'fail')
        self.assertIn('push_tokens', note)


if __name__ == '__main__':
    unittest.main()
