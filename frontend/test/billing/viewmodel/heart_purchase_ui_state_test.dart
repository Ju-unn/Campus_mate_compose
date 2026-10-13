import 'package:campus_mate/billing/model/billing_repository.dart';
import 'package:campus_mate/billing/model/heart_bundles.dart';
import 'package:campus_mate/billing/model/heart_purchase_notice.dart';
import 'package:campus_mate/billing/model/store_purchase.dart';
import 'package:campus_mate/billing/viewmodel/heart_purchase_ui_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_heart_store_gateway.dart';

void main() {
  final ready = HeartPurchaseUiState(
    availability: HeartStoreAvailability.available,
    prices: storePricesWon(),
    accountToken: 'a' * 64,
    bonus: const FirstPurchaseBonus(hearts: 50, minProductHearts: 100),
  );

  test('처음 고른 상품은 앱 표의 추천 번들(100하트)과 같다', () {
    expect(defaultHeartProductId, heartBundles[defaultHeartBundleIndex].productId);
    expect(const HeartPurchaseUiState().selectedBundle.hearts, 100);
  });

  test('canBuy — 스토어 열림 · 쉬는 중 · 계정 표시 · 그 상품 가격이 모두 있어야 한다', () {
    expect(ready.canBuy('heart_100'), isTrue);
    expect(const HeartPurchaseUiState().canBuy('heart_100'), isFalse, reason: '읽는 중');
    expect(ready.copyWith(phase: HeartPurchasePhase.verifying).canBuy('heart_100'), isFalse);
    expect(ready.copyWith(accountToken: null).canBuy('heart_100'), isFalse);
    expect(ready.copyWith(prices: {}).canBuy('heart_100'), isFalse);
    expect(ready.copyWith(availability: HeartStoreAvailability.unavailable).canBuy('heart_100'), isFalse);
  });

  test('bonusFor — 자격이 있을 때 100하트 이상에만, 자격이 없으면 아무 데도', () {
    expect([for (final b in heartBundles) ready.bonusFor(b)], [null, 50, 50, 50, 50]);
    expect([for (final b in heartBundles) ready.copyWith(bonus: null).bonusFor(b)], [null, null, null, null, null]);
  });

  test('priced · selectedBundle 은 스토어 가격을 씌운다', () {
    final state = ready.copyWith(
      prices: {'heart_200': const StorePrice(label: r'US$8.99')},
      selectedProductId: 'heart_200',
    );

    expect(state.selectedBundle.priceLabel, r'US$8.99');
    expect(state.priced(heartBundles.first).priceLabel, '3,000원');
  });

  test('copyWith — 넘기지 않은 칸은 그대로, null 을 넘기면 지운다', () {
    final noticed = ready.copyWith(banner: HeartPurchaseNotice.pending, toast: const NoticeToast(HeartPurchaseNotice.canceled));

    expect(noticed.copyWith(phase: HeartPurchasePhase.idle).banner, HeartPurchaseNotice.pending);
    expect(noticed.copyWith(banner: null).banner, isNull);
    expect(noticed.copyWith(toast: null).toast, isNull);
    expect(noticed.copyWith(toast: null).accountToken, 'a' * 64);
  });

  test('토스트 글자 — 성공은 서버 숫자로(사용자 확정 10-13), 안내는 pen 글자', () {
    expect(const GrantedToast(hearts: 100, bonusHearts: 50).message, '150하트가 들어왔어요(보너스 50 포함)');
    expect(const GrantedToast(hearts: 800, bonusHearts: 0).message, '800하트가 들어왔어요');
    expect(const NoticeToast(HeartPurchaseNotice.alreadyProcessed).message, '이미 처리된 결제예요');
  });
}
