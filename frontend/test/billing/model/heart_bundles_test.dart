import 'package:campus_mate/billing/model/heart_bundles.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('번들 5장은 pen `IAy1j` 카드 값과 같다(목 — 서버 값 미정)', () {
    expect(
      [
        for (final b in heartBundles)
          (b.hearts, b.price, b.originalPrice, b.discountPercent, b.isMaxDiscount, b.isRecommended),
      ],
      [
        (50, 3000, null, null, false, false),
        (100, 5700, 6000, 5, false, true),
        (200, 10800, 12000, 10, false, false),
        (400, 20400, 24000, 15, false, false),
        (800, 38400, 48000, 20, true, false),
      ],
    );
  });

  test('처음 고른 번들은 "추천" 인 100하트 하나다', () {
    expect(heartBundles[defaultHeartBundleIndex].hearts, 100);
    expect(heartBundles.where((b) => b.isRecommended), [heartBundles[defaultHeartBundleIndex]]);
  });

  test('할인 가격 = 원가 × (100 − 할인율)%  — pen 값이 서로 맞는다', () {
    for (final b in heartBundles.where((b) => b.originalPrice != null)) {
      expect(b.originalPrice! * (100 - b.discountPercent!) ~/ 100, b.price, reason: b.quantityLabel);
    }
  });

  test('번들 그림 5장이 모두 자산에 있다', () {
    for (final b in heartBundles) {
      expect(b.asset, 'assets/images/heart-bundle-${b.hearts}-v1.png');
    }
  });

  test('formatWon 은 천 단위마다 쉼표', () {
    expect(
      [
        for (final v in [0, 999, 1000, 3000, 38400, 1234567, -1500]) formatWon(v),
      ],
      ['0', '999', '1,000', '3,000', '38,400', '1,234,567', '-1,500'],
    );
  });
}
