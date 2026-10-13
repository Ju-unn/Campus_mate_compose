import 'package:campus_mate/billing/model/payment_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PaymentStore storeOn(TargetPlatform platform) {
    debugDefaultTargetPlatformOverride = platform;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container.read(paymentStoreProvider);
  }

  test('iOS 는 App Store, 안드로이드는 구글 플레이', () {
    expect(storeOn(TargetPlatform.iOS), PaymentStore.appStore);
  });

  test('안드로이드는 구글 플레이', () {
    expect(storeOn(TargetPlatform.android), PaymentStore.googlePlay);
  });

  test('결제 안내 두 줄 — 구글은 pen `bBjRD` 글자 그대로, App Store 는 같은 꼴에 스토어 이름만 바꾼다(pen 후속)', () {
    expect([for (final store in PaymentStore.values) (store.name, store.paymentLine, store.refundLine)], [
      ('googlePlay', '결제는 구글 플레이로 처리돼요', '결제 취소 · 환불은 구글 플레이 환불 절차를 따라요'),
      ('appStore', '결제는 App Store로 처리돼요', '결제 취소 · 환불은 App Store 환불 절차를 따라요'),
    ]);
  });

  test('App Store 문구에도 하네스 금지어(환급 · 선물 · 송금 · 현금 · 출금)가 없다(E-HEART-49)', () {
    final lines = [for (final store in PaymentStore.values) ...[store.paymentLine, store.refundLine]];
    for (final word in ['환급', '선물', '송금', '현금', '출금']) {
      expect(lines.where((line) => line.contains(word)), isEmpty, reason: word);
    }
  });
}
