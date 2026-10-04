"""공용 가짜 서버들이 `tools.call` 이 넘기는 더한 키워드(`retry=False` 등)를 받는지 — 저장소 루트에서 `python -m unittest e2e.test_fake_options`.

#268 로 비멱등 호출이 `tools.call(..., retry=False)` 를 부르게 됐다. 가짜 `__call__` 에 `**options` 가 없으면
`TypeError: __call__() got an unexpected keyword argument 'retry'` 로 그 호출을 쓰는 시험이 전부 깨진다(CI 는 e2e 시험을 안 돌린다).
가짜는 키워드를 무시하고 똑같이 답해야 한다 — 실제 재시도 동작은 test_resilience 가 본다."""

import unittest

from e2e import test_area1, test_area3, test_area3_safe, test_area4, test_area4_set2, test_area5_api, test_notify_factory

URL = 'https://sb.test/rest/v1/profiles?id=eq.id-1&select=status'

FAKES = {
    'test_area1.FakeServer': test_area1.FakeServer,
    'test_area3.Fake': test_area3.Fake,
    'test_area3_safe.SafeFake': test_area3_safe.SafeFake,
    'test_area4.FakeDb': test_area4.FakeDb,
    'test_area4_set2.Db': test_area4_set2.Db,
    'test_area5_api.ApiFake': test_area5_api.ApiFake,
    'test_notify_factory.Recorder': test_notify_factory.Recorder,
}


class FakeOptionsTest(unittest.TestCase):
    def test_every_shared_fake_accepts_retry_false_and_answers_the_same(self):
        for name, make in FAKES.items():
            with self.subTest(fake=name):
                plain = make()('GET', URL)
                once = make()('GET', URL, retry=False)
                self.assertEqual(tuple(once), tuple(plain))

    def test_extra_keywords_beyond_retry_are_ignored_too(self):
        for name, make in FAKES.items():
            with self.subTest(fake=name):
                self.assertEqual(tuple(make()('GET', URL, retry=False, tries=1)), tuple(make()('GET', URL)))


if __name__ == '__main__':
    unittest.main()
