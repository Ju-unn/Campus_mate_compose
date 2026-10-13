import 'package:campus_mate/billing/model/heart_purchase_notice.dart';
import 'package:campus_mate/billing/model/payment_store.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('문구는 pen 15e-8 `JGoPI` 여덟 개와 글자까지 같다(환불 안내는 pen 에 없다 — 아래)', () {
    expect(
      [
        for (final notice in HeartPurchaseNotice.values.where((n) => n != HeartPurchaseNotice.revoked))
          (notice.name, notice.title, notice.caption),
      ],
      [
        ('canceled', '결제를 취소했어요', null),
        ('alreadyProcessed', '이미 처리된 결제예요', null),
        ('pending', '결제 확인을 기다리고 있어요', '확인되면 하트가 들어와요'),
        ('delayed', '하트 지급이 늦어지고 있어요', '앱을 다시 열면 이어서 들어와요'),
        ('failed', '결제가 되지 않았어요', '결제 수단을 확인하고 다시 시도해 주세요'),
        ('invalid', '결제를 확인하지 못했어요', '문제가 계속되면 appmailerl4538@gmail.com 으로 알려 주세요'),
        ('otherAccount', '다른 계정으로 결제한 하트예요', '결제한 계정으로 로그인하면 들어와요'),
        ('unavailable', '지금은 하트를 살 수 없어요', '구글 플레이에 로그인했는지 확인해 주세요'),
      ],
    );
  });

  test('환불된 애플 거래(422 purchase_revoked) 안내는 짧은 토스트 "환불된 결제예요"(pen 후속)', () {
    expect((HeartPurchaseNotice.revoked.title, HeartPurchaseNotice.revoked.caption), ('환불된 결제예요', null));
  });

  test('스토어 이름이 든 설명은 결제 불가 하나 — App Store 에서는 App Store 로(pen 후속), 나머지는 두 스토어가 같다', () {
    expect(HeartPurchaseNotice.unavailable.captionOn(PaymentStore.appStore), 'App Store에 로그인했는지 확인해 주세요');
    expect(HeartPurchaseNotice.unavailable.captionOn(PaymentStore.googlePlay), '구글 플레이에 로그인했는지 확인해 주세요');
    for (final notice in HeartPurchaseNotice.values.where((n) => n != HeartPurchaseNotice.unavailable)) {
      expect(notice.captionOn(PaymentStore.appStore), notice.caption, reason: notice.name);
    }
  });

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
