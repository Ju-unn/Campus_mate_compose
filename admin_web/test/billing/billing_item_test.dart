import 'package:campus_mate_admin/billing/billing_item.dart';
import 'package:campus_mate_admin/billing/revenue_chart.dart';
import 'package:campus_mate_admin/users/user_item.dart';
import 'package:campus_mate_admin/widgets/status_badge.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/user_fakes.dart';

void main() {
  test('원 표시: 천 단위 쉼표, 0 은 ₩0', () {
    expect(formatWon(1284000), '₩1,284,000');
    expect(formatWon(285000), '₩285,000');
    expect(formatWon(900), '₩900');
    expect(formatWon(0), '₩0');
  });

  test('월 · 날짜 글자는 서버 한국 날짜를 시간대 계산 없이 그대로 자른다', () {
    expect(formatMonth('2026-10'), '2026년 10월');
    expect(formatMonth('2026-09'), '2026년 9월');
    expect(formatMonthDay('2026-10-18'), '10/18');
    expect(formatMonthDay('2026-09-05'), '9/5');
  });

  test('구매 상태 배지: 완료 success · 환불됨 danger · 그 밖 neutral(글자 그대로)', () {
    expect(purchaseStatusBadge('granted'), ('완료', StatusTone.success));
    expect(purchaseStatusBadge('refunded'), ('환불됨', StatusTone.danger));
    expect(purchaseStatusBadge('pending'), ('pending', StatusTone.neutral));
  });

  group('그래프 눈금(pen 0 · 10만 · 20만 · 30만, 최댓값은 데이터에 맞춘다)', () {
    test('눈금 3칸이 가장 큰 날을 덮는 1 · 2 · 5 × 10^k', () {
      expect(niceTickStep(285000), 100000); // pen 예시 → 30만
      expect(niceTickStep(300000), 100000);
      expect(niceTickStep(300001), 200000);
      expect(niceTickStep(120000), 50000);
      expect(niceTickStep(8000), 5000);
      expect(niceTickStep(1), 1000);
      expect(niceTickStep(0), 100000);
    });

    test('눈금 글자', () {
      expect([for (final v in [0, 100000, 200000, 300000]) tickLabel(v)], ['0', '10만', '20만', '30만']);
      expect(tickLabel(50000), '5만');
      expect(tickLabel(150000), '15만');
      expect(tickLabel(75000), '7.5만');
      expect(tickLabel(5000), '5천');
      expect(tickLabel(2500), '2500');
    });

    test('화면 읽기 한 줄: 합계 + 가장 많은 날(같으면 더 최근), 매출이 없으면 합계만', () {
      final days = [for (final row in thirtyDays([10000, 30000, 30000, 5000])) DailyRevenue.fromJson(row)];
      expect(revenueSummaryLabel(days), '최근 30일 매출 합계 ₩75,000, 가장 많은 날 10/17 ₩30,000');
      final none = [for (final row in thirtyDays([])) DailyRevenue.fromJson(row)];
      expect(revenueSummaryLabel(none), '최근 30일 매출 합계 ₩0');
    });
  });

  group('사용자 글자 규칙', () {
    test('프로필 id 줄임: 앞 4 + … + 뒤 3', () {
      expect(shortProfileId('8f3a1b2c-0000-4000-8000-000000000c21'), '8f3a…c21');
      expect(shortProfileId('abc'), 'abc');
    });

    test('날짜는 한국 시간(UTC+9)으로 자른다 — UTC 15:30 은 다음 날', () {
      expect(formatKstDate(DateTime.utc(2026, 9, 29, 15, 30)), '2026-09-30');
    });

    test('상태 · 로그인 방식 · 스토어 · 원장 종류 글자(모르는 값은 그대로)', () {
      expect(userStatusBadge('active'), ('승인', StatusTone.success));
      expect(userStatusBadge('suspended'), ('정지', StatusTone.danger));
      expect(userStatusBadge('withdrawn'), ('탈퇴', StatusTone.neutral));
      expect(userStatusBadge('pending'), ('가입 중', StatusTone.warning));
      expect(userStatusBadge('x'), ('x', StatusTone.neutral));
      expect([loginProviderName('kakao'), loginProviderName('google'), loginProviderName('apple'), loginProviderName('x')], ['카카오', '구글', '애플', 'x']);
      expect([storeName('play_store'), storeName('app_store')], ['구글 플레이', '앱스토어']);
      expect([heartReasonLabel('free_task'), heartReasonLabel('extra_card'), heartReasonLabel('admin_adjust'), heartReasonLabel('zzz')], ['무료 인증샷 보상', '카드 열기', '관리자 조정', 'zzz']);
    });

    test('상품 이름: heart_N 이면 "하트 N개", 모르는 id 는 id 글자 그대로', () {
      expect(productDisplayName('heart_100'), '하트 100개');
      expect(productDisplayName('heart_5'), '하트 5개');
      expect(productDisplayName('pack_big'), 'pack_big');
      expect(productDisplayName('hearts_100'), 'hearts_100');
      expect(productDisplayName('heart_100_bonus'), 'heart_100_bonus');
      final purchase = PurchaseEntry.fromJson({
        'id': 'p', 'store': 'play_store', 'product_id': 'pack_big', 'status': 'granted', 'is_test': false, 'granted_hearts': 110, 'bonus_hearts': 10, 'purchased_at': '2026-10-10T09:20:00+00:00',
      });
      expect(purchase.productName, 'pack_big');
      expect(purchase.grantedHearts, 110);
    });

    test('모양이 틀린 응답은 FormatException', () {
      expect(() => UserSummary.fromJson({'id': 'u'}), throwsFormatException);
      expect(() => UserDetail.fromJson({}), throwsFormatException);
      expect(() => BillingOrder.fromJson({}), throwsFormatException);
    });
  });
}
