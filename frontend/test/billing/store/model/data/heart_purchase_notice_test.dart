import 'package:campus_mate/billing/store/model/data/heart_purchase_notice.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 안내 글자(제목 · 설명)는 view 쪽 확장이 정한다 — test/billing/store/view/heart_store_text_test.dart.
  test('토스트는 취소 · 이미 처리 · 환불 셋뿐이고 나머지는 앱바 아래 배너다', () {
    expect(HeartPurchaseNotice.values.where((n) => !n.isBanner), [
      HeartPurchaseNotice.canceled,
      HeartPurchaseNotice.alreadyProcessed,
      HeartPurchaseNotice.revoked,
    ]);
  });

  test('빨간 오류 배너는 결제 실패 · 확인 실패 · 결제 불가 셋이다(pen 채움 #FAEFEC)', () {
    expect(HeartPurchaseNotice.values.where((n) => n.isError), [
      HeartPurchaseNotice.failed,
      HeartPurchaseNotice.invalid,
      HeartPurchaseNotice.unavailable,
    ]);
  });

  group('서버 확인 실패 → 안내(문구가 아니라 code 로 가른다)', () {
    test('409 purchase_other_account → 다른 계정', () {
      expect(
        HeartPurchaseNotice.fromVerifyFailure(const ServerRejectedFailure('x', code: 'purchase_other_account')),
        HeartPurchaseNotice.otherAccount,
      );
    });

    test('409 purchase_token_used → 이미 처리', () {
      expect(
        HeartPurchaseNotice.fromVerifyFailure(const ServerRejectedFailure('x', code: 'purchase_token_used')),
        HeartPurchaseNotice.alreadyProcessed,
      );
    });

    test('422 purchase_revoked → 환불(같은 422 라도 purchase_invalid 와 다르다)', () {
      expect(
        HeartPurchaseNotice.fromVerifyFailure(const ServerRejectedFailure('환불된 결제예요', code: 'purchase_revoked')),
        HeartPurchaseNotice.revoked,
      );
    });

    test('422 purchase_invalid → 확인 실패(서버 문구가 달라도 pen 문구)', () {
      final notice = HeartPurchaseNotice.fromVerifyFailure(
        const ServerRejectedFailure('결제를 확인하지 못했어요. 문제가 계속되면 문의해 주세요', code: 'purchase_invalid'),
      );
      expect(notice, HeartPurchaseNotice.invalid);
    });

    test('503 · 네트워크 · 모르는 실패는 모두 지급 지연 — 구매를 끝내지 않고 다시 보낸다', () {
      for (final failure in const <Failure>[
        ServerUnavailableFailure(),
        NetworkFailure(),
        UnknownFailure(),
        ServerRejectedFailure('학생증 인증이 필요해요'),
      ]) {
        expect(HeartPurchaseNotice.fromVerifyFailure(failure), HeartPurchaseNotice.delayed, reason: '$failure');
      }
    });

    test('같은 토큰을 다시 보내도 결과가 바뀌지 않는 안내만 "끝난 토큰" 이다', () {
      expect(HeartPurchaseNotice.values.where((n) => n.isFinalForToken), [
        HeartPurchaseNotice.alreadyProcessed,
        HeartPurchaseNotice.revoked,
        HeartPurchaseNotice.invalid,
        HeartPurchaseNotice.otherAccount,
      ]);
    });

    test('거절인데도 구매를 끝내는(finish) 안내는 이미 처리 · 환불 둘 — 확인 실패 · 다른 계정은 끝내지 않는다', () {
      expect(HeartPurchaseNotice.values.where((n) => n.finishesPurchase), [
        HeartPurchaseNotice.alreadyProcessed,
        HeartPurchaseNotice.revoked,
      ]);
    });
  });
}
