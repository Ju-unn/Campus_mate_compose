import 'package:campus_mate/billing/model/heart_store_gateway.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('기본 창구(NoHeartStoreGateway)는 아무것도 하지 않는다 — 시험 · iOS · 웹', () async {
    const inert = NoHeartStoreGateway();

    expect(await inert.isAvailable(), isFalse);
    expect(await inert.loadPrices({'heart_100'}), isEmpty);
    expect(await inert.buy('heart_100', 'a' * 64), isFalse);
    await expectLater(inert.recover(), completes);
    expect(await inert.events.isEmpty, isTrue);
  });

  test('provider 기본값은 그 아무것도 하지 않는 창구다 — 진짜 창구는 안드로이드 진입점(main.dart)만 끼운다', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(heartStoreGatewayProvider), isA<NoHeartStoreGateway>());
  });
}
