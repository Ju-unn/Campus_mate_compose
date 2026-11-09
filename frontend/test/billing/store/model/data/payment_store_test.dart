import 'package:campus_mate/billing/store/model/data/payment_store.dart';
import 'package:campus_mate/billing/store/model/repository/payment_store_provider.dart';
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

  // 결제 안내 두 줄의 글자는 view 쪽 확장이 정한다 — test/billing/store/view/heart_store_text_test.dart.
}
