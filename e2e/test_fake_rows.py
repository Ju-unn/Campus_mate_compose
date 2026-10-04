"""공용 가짜 서버가 PostgREST 처럼 여러 행 POST 의 키 불일치를 거절하는지.
저장소 루트에서 `python -m unittest e2e.test_fake_rows`.
운영 PostgREST 는 배열로 넣을 때 행마다 키 집합이 다르면 400 PGRST102 "All object keys must match" 로 돌려준다.
(E-SAFE-05 가 시스템 줄에만 kind 를 넣어 운영에서 막혔다 — 가짜가 받아 줘서 시험에서는 못 봤다.)"""
import unittest

from e2e import test_area3, test_area3_safe

URL = 'https://sb.test/rest/v1/messages'
FAKES = {'test_area3.Fake': test_area3.Fake, 'test_area3_safe.SafeFake': test_area3_safe.SafeFake}


class FakeRowsTest(unittest.TestCase):
    def test_rows_with_different_keys_are_400_and_nothing_is_saved(self):
        for name, make in FAKES.items():
            with self.subTest(fake=name):
                fake = make()
                got = fake('POST', URL, body=[{'id': 'a', 'body': 'x'}, {'id': 'b', 'kind': 'trust_accept', 'body': 'y'}])
                self.assertEqual(got.status, 400)
                self.assertEqual(got.body['code'], 'PGRST102')
                self.assertEqual(fake.tables.get('messages', []), [])

    def test_rows_with_the_same_keys_are_saved(self):
        for name, make in FAKES.items():
            with self.subTest(fake=name):
                fake = make()
                got = fake('POST', URL, body=[{'id': 'a', 'kind': 'text', 'body': 'x'}, {'id': 'b', 'kind': 'trust_accept', 'body': 'y'}])
                self.assertEqual(got.status, 201)
                self.assertEqual(len(fake.tables['messages']), 2)

    def test_one_row_and_a_single_object_are_saved(self):
        for name, make in FAKES.items():
            with self.subTest(fake=name):
                fake = make()
                self.assertEqual(fake('POST', URL, body={'id': 'a', 'body': 'x'}).status, 201)
                self.assertEqual(fake('POST', URL, body=[{'id': 'b', 'body': 'y'}]).status, 201)


if __name__ == '__main__':
    unittest.main()
