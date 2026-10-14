"""E-HEART-50 · E-SET-57(약관 두 가설)의 PC 쪽 시험 — 노션 · 폰 · 운영 없이 가짜 페이지 · 가짜 앱. 저장소 루트에서 `python -m unittest e2e.test_area4_terms`."""

import json
import unittest
from unittest import mock

from e2e import area1, area4_terms, tools
from e2e.test_area3_phone import said
from e2e.test_area5_read import OURS, ReadBase, StepApp
from e2e.tools import Blocked

BROWSER = 'topResumedActivity=ActivityRecord{1 u0 com.android.chrome/org.chromium.chrome.browser.ChromeTabbedActivity t9}'
PAGE, POLICY = area4_terms.page_ids()
SENTENCE = area4_terms.SENTENCE
PART1, PART2 = area4_terms.PART1, area4_terms.PART2


def page(order, titles):
    """[order] 는 약관동의 페이지의 블록 id 순서, [titles] 는 id → 글(없으면 안 받은 블록)."""
    blocks = {PAGE: {'value': {'value': {'content': order}}}}
    for key, title in titles.items():
        blocks[key] = {'value': {'value': {'properties': {'title': [[title]]}}}}
    return blocks


def good():
    return page(['h1', 'a', 'b', 'h2', 'c'], {'h1': PART1, 'a': SENTENCE, 'b': '다른 조항', 'h2': PART2, 'c': '청약철회와 환불'})


class HeartTest(unittest.TestCase):
    def run50(self, blocks, ids=(PAGE, POLICY)):
        with mock.patch.object(area4_terms, 'fetch_page', lambda page_id: blocks), mock.patch.object(area4_terms, 'page_ids', lambda: ids):
            return area4_terms.heart_50(None)

    def test_heart_clause_between_part_one_and_part_two_passes(self):
        result, note = self.run50(good())
        self.assertEqual(result, 'pass', note)

    def test_missing_sentence_fails(self):
        blocks = good()
        blocks['a']['value']['value']['properties']['title'] = [['다른 문장']]
        result, note = self.run50(blocks)
        self.assertEqual(result, 'fail', note)

    def test_sentence_only_in_part_two_fails(self):
        blocks = page(['h1', 'b', 'h2', 'a'], {'h1': PART1, 'b': 'x', 'h2': PART2, 'a': SENTENCE})
        result, note = self.run50(blocks)
        self.assertEqual(result, 'fail', note)
        self.assertIn('I 부 안이 아님', note)

    def test_sentence_before_part_one_header_fails(self):
        blocks = page(['a', 'h1', 'h2'], {'a': SENTENCE, 'h1': PART1, 'h2': PART2})
        self.assertEqual(self.run50(blocks)[0], 'fail')

    def test_sentence_twice_fails(self):
        blocks = page(['h1', 'a', 'c', 'h2'], {'h1': PART1, 'a': SENTENCE, 'c': SENTENCE, 'h2': PART2})
        self.assertEqual(self.run50(blocks)[0], 'fail')

    def test_extra_spaces_and_line_breaks_do_not_hide_the_sentence(self):
        blocks = good()
        blocks['a']['value']['value']['properties']['title'] = [[SENTENCE.replace(' ', '  ', 2) + '\n']]
        self.assertEqual(self.run50(blocks)[0], 'pass')

    def test_bold_word_split_into_parts_still_reads_as_one_sentence(self):
        blocks = good()  # 노션은 굵은 "하트" 를 따로 떼어 [["하트", [["b"]]], ["는 …"]] 로 준다
        blocks['a']['value']['value']['properties']['title'] = [['하트', [['b']]], [SENTENCE.removeprefix('하트')]]
        self.assertEqual(self.run50(blocks)[0], 'pass')

    def test_privacy_policy_on_the_same_page_as_the_terms_fails(self):
        result, note = self.run50(good(), ids=(PAGE, PAGE))
        self.assertEqual(result, 'fail', note)
        self.assertIn('별도 페이지', note)

    def test_page_without_the_part_headers_is_blocked_not_fail(self):
        for blocks in ({}, page(['a'], {'a': SENTENCE}), page(['h1', 'a'], {'h1': PART1, 'a': SENTENCE})):
            with self.assertRaises(Blocked):
                self.run50(blocks)

    def test_old_part_two_header_is_not_taken_for_part_two(self):
        blocks = page(['h1', 'a', 'old'], {'h1': PART1, 'a': SENTENCE, 'old': '2부. 개인정보 처리방침'})
        with self.assertRaises(Blocked):
            self.run50(blocks)

    def test_block_in_part_one_but_not_received_is_blocked_not_fail(self):
        blocks = good()
        blocks[PAGE]['value']['value']['content'].insert(2, 'later-chunk')  # 순서엔 있고 블록 글은 받은 chunk 에 없음
        with self.assertRaises(Blocked) as raised:
            self.run50(blocks)
        self.assertIn('모자람', str(raised.exception))

    def test_part_two_header_beyond_the_received_chunks_is_blocked(self):
        blocks = page(['h1', 'a', 'b', 'h2'], {'h1': PART1, 'a': SENTENCE, 'b': 'x'})  # h2 는 순서에만 있다
        with self.assertRaises(Blocked):
            self.run50(blocks)


class FetchTest(unittest.TestCase):
    """loadCachedPageChunkV2 를 cursor 로 이어 받는다 — 첫 chunk(100블록)보다 I 부가 길다."""

    def replies(self, *chunks):
        sent = []

        def urlopen(request, timeout):
            sent.append(json.loads(request.data))
            blocks, stack = chunks[len(sent) - 1]
            reply = mock.MagicMock()
            reply.__enter__.return_value.read.return_value = json.dumps({'recordMap': {'block': blocks}, 'cursor': {'stack': stack}}).encode()
            return reply

        return sent, mock.patch.object(area4_terms.urllib.request, 'urlopen', urlopen)

    def test_follows_the_cursor_until_the_stack_is_empty(self):
        more = [[{'table': 'block', 'id': 'x', 'index': 100}]]
        sent, patch = self.replies(({'a': 1}, more), ({'b': 2}, []))
        with patch:
            blocks = area4_terms.fetch_page(PAGE)
        self.assertEqual(blocks, {'a': 1, 'b': 2})
        self.assertEqual([(body['chunkNumber'], body['cursor']['stack']) for body in sent], [(0, []), (1, more)])

    def test_stops_after_the_chunk_limit(self):
        more = [[{'table': 'block', 'id': 'x', 'index': 1}]]
        sent, patch = self.replies(*[({str(i): i}, more) for i in range(area4_terms.CHUNKS + 1)])
        with patch:
            area4_terms.fetch_page(PAGE)
        self.assertEqual(len(sent), area4_terms.CHUNKS)

    def test_download_failure_is_blocked(self):
        with mock.patch.object(area4_terms.urllib.request, 'urlopen', side_effect=OSError('offline')), self.assertRaises(Blocked):
            area4_terms.fetch_page(PAGE)


class TermsViewTest(ReadBase):
    def run57(self, top, texts):
        events = []
        dump = '<hierarchy>' + ''.join(f'<node text="{t}" content-desc=""/>' for t in texts) + '</hierarchy>'
        app = StepApp(lambda job: said(), ['terms'], events, top=top)
        with mock.patch.object(area4_terms.time, 'sleep'), mock.patch.object(area4_terms.notify, '_ui_dump', lambda serial: dump), \
                mock.patch.object(area4_terms, '_front', lambda serial: events.append('front')):
            result, app = self.case('E-SET-57', {}, app)
        return result, events

    def test_title_visible_without_login_passes_and_the_app_is_brought_back(self):
        (result, note), events = self.run57(BROWSER, ['약관동의', PART1])
        self.assertEqual(result, 'pass', note)
        self.assertIn('front', events)

    def test_login_wall_fails(self):
        (result, note), _ = self.run57(BROWSER, ['약관동의', 'Log in', 'Continue with Google'])
        self.assertEqual(result, 'fail', note)
        self.assertIn('로그인', note)

    def test_login_wall_without_the_title_fails_not_blocked(self):
        (result, note), _ = self.run57(BROWSER, ['Sign up', 'Notion'])
        self.assertEqual(result, 'fail', note)

    def test_our_app_still_in_front_fails_and_reads_no_screen(self):
        (result, note), events = self.run57(OURS, [])
        self.assertEqual(result, 'fail', note)
        self.assertIn('front', events)  # 실패해도 앱은 앞으로 되돌린다

    def test_a_word_that_only_contains_the_login_words_does_not_fail(self):
        (result, note), _ = self.run57(BROWSER, ['약관동의', 'dialog in progress', 'design up'])
        self.assertEqual(result, 'pass', note)

    def test_the_words_that_tripped_are_named_in_the_note(self):
        (result, note), _ = self.run57(BROWSER, ['약관동의', 'Log in'])
        self.assertEqual((result, 'log in' in note), ('fail', True))

    def test_text_not_readable_is_blocked_not_fail(self):
        (result, note), _ = self.run57(BROWSER, ['', 'x'])
        self.assertEqual(result, 'blocked', note)

    def test_chrome_first_run_screen_is_blocked(self):
        (result, note), _ = self.run57(BROWSER, ['Welcome to Chrome', 'Use without an account'])
        self.assertEqual(result, 'blocked', note)
        self.assertIn('첫 실행', note)


class RegistryTest(unittest.TestCase):
    def test_registered(self):
        self.assertEqual(area1.BUNDLES['area4-terms'], ['E-HEART-50', 'E-SET-57'])
        self.assertIs(area1.PHONE['E-SET-57'], area4_terms.p_set_57)
        self.assertIs(area1.CASES['E-HEART-50'], area4_terms.heart_50)
        self.assertGreater(tools.CASE_LIMITS['E-SET-57'], area4_terms.PAGE_WAIT + area4_terms.FRONT_WAIT)
        from e2e import __main__ as main
        self.assertIn('from e2e import area4_terms', main.__loader__.get_source('e2e.__main__'))

    def test_the_app_stops_once_where_the_pc_waits_and_is_wired_in(self):
        folder = tools.ROOT / 'frontend' / 'integration_test'
        text = (folder / 'area1_terms.dart').read_text(encoding='utf-8')
        self.assertEqual(text.count("step('terms')"), 1)
        self.assertIn("'이용약관 보기'", text)
        wiring = (folder / 'area1.dart').read_text(encoding='utf-8')
        self.assertIn("part 'area1_terms.dart';", wiring)
        self.assertIn('..._termsCases,', wiring)

    def test_the_pages_and_site_come_from_the_app_not_a_copy(self):
        links = area4_terms.LINKS.read_text(encoding='utf-8')
        self.assertIn(f"_site = '{area4_terms.SITE}'", links)
        self.assertIn(f"_termsPage = '$_site/{PAGE.replace('-', '')}'", links)
        self.assertIn(f"_privacyPage = '$_site/{POLICY.replace('-', '')}'", links)
        self.assertNotEqual(PAGE, POLICY)


if __name__ == '__main__':
    unittest.main()
