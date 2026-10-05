"""알림을 읽는 폰 가설(E-CHAT-32 · E-GATE-43 · E-REF-18 · E-ONB-61 · E-CARD-02 · PUSH A1 의 _Scene)이 시작할 때 푸시 연결을 점검하는지 — 폰 · 운영 없이.
저장소 루트에서 `python -m unittest e2e.test_ensure_delivery_wiring`.

점검이 막히면(`notify.ensure_delivery` 가 Blocked) 계정도 만들지 않고 앱도 켜지 않은 채 blocked 로 끝나야 한다 —
푸시 연결이 죽은 폰에서는 "알림이 안 왔다" 가 폰 탓인지 앱 탓인지 가릴 수 없다."""

import unittest
from unittest import mock

from e2e import area1, notify, tools
from e2e import area1_b2, area1_b5, area2_phone3, area3_phone3, area4_push  # noqa: F401 — 가설을 area1.PHONE 에 등록한다
from e2e.test_area1 import Base
from e2e.test_area1_phone import FakePhone
from e2e.tools import Blocked

CASES = ('E-CHAT-32', 'E-GATE-43', 'E-REF-18', 'E-ONB-61', 'E-CARD-02', 'E-PUSH-10', 'E-PUSH-74')  # PUSH A1 은 한 도구(_Scene)로 시작해 대표 둘이면 충분
REASON = '푸시 연결 점검이 막힘(시험용)'


class WiringTest(Base):
    def setUp(self):
        super().setUp()
        for patcher in (mock.patch.object(notify, 'ensure_delivery', mock.Mock(side_effect=Blocked(REASON))),
                        mock.patch.object(notify, 'require_daytime', lambda now=None: None),
                        mock.patch.object(tools, 'adb', lambda *a, **k: ''),
                        mock.patch.object(tools, 'call', mock.Mock(side_effect=AssertionError('점검이 막혔는데 서버를 불렀다')))):
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_each_case_checks_delivery_first_and_stops_before_making_accounts_or_starting_the_app(self):
        for case in CASES:
            with self.subTest(case=case):
                phone = FakePhone()
                phone.serial = 'S'
                result = area1.attempt_phone(self.run, case, phone)
                self.assertEqual(result, ('blocked', REASON))
                self.assertEqual(phone.jobs, [])
                notify.ensure_delivery.assert_called_with('S')

    def test_the_check_is_given_the_phones_serial(self):
        phone = FakePhone()
        phone.serial = 'R5CT'
        area1.attempt_phone(self.run, 'E-REF-18', phone)
        notify.ensure_delivery.assert_called_with('R5CT')


if __name__ == '__main__':
    unittest.main()
