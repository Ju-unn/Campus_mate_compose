import 'package:campus_mate/billing/model/heart_bundles.dart';
import 'package:campus_mate/billing/model/store_purchase.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('번들 5장은 pen `IAy1j` 카드 값과 같다 — 원가 · 할인율은 판매가와 60원 기준가로 계산한다', () {
    expect(
      [
        for (final b in heartBundles)
          (b.productId, b.hearts, b.price, b.originalPrice, b.discountPercent, b.isMaxDiscount, b.isRecommended),
      ],
      [
        ('heart_50', 50, 3000, null, null, false, false),
        ('heart_100', 100, 5700, 6000, 5, false, true),
        ('heart_200', 200, 10800, 12000, 10, false, false),
        ('heart_400', 400, 20400, 24000, 15, false, false),
        ('heart_800', 800, 38400, 48000, 20, true, false),
      ],
    );
  });

  test('상품 ID 는 서버 상품표(heart_50 … heart_800)와 같은 다섯 개다', () {
    expect(heartProductIds, {'heart_50', 'heart_100', 'heart_200', 'heart_400', 'heart_800'});
  });

  test('처음 고른 번들은 "추천" 인 100하트 하나다', () {
    expect(heartBundles[defaultHeartBundleIndex].hearts, 100);
    expect(heartBundles.where((b) => b.isRecommended), [heartBundles[defaultHeartBundleIndex]]);
  });

  test('번들 그림 5장이 모두 자산에 있다', () {
    for (final b in heartBundles) {
      expect(b.asset, 'assets/images/heart-bundle-${b.hearts}-v1.png');
    }
  });

  group('스토어 가격 합치기(계획서 6-3)', () {
    final hundred = heartBundles[defaultHeartBundleIndex];

    test('스토어 가격이 없으면 앱 상수 가격 그대로 "5,700원"', () {
      final bundle = hundred.withStorePrice(null);
      expect((bundle.price, bundle.priceLabel, bundle.discountPercent), (5700, '5,700원', 5));
    });

    test('원화 가격이 오면 그 값으로 바꾸고 원가 · 할인율을 다시 계산한다', () {
      final bundle = hundred.withStorePrice(const StorePrice(label: '₩5,400', won: 5400));
      expect((bundle.price, bundle.priceLabel, bundle.originalPrice, bundle.discountPercent), (5400, '5,400원', 6000, 10));
    });

    test('원화 가격이 기준가(하트 × 60원)와 같으면 원가 · 할인을 보이지 않는다', () {
      final bundle = hundred.withStorePrice(const StorePrice(label: '₩6,000', won: 6000));
      expect((bundle.originalPrice, bundle.discountPercent, bundle.showsDiscount), (null, null, false));
    });

    test('원화가 아니면 스토어 글자를 그대로 쓰고 할인은 숨긴다', () {
      final bundle = hundred.withStorePrice(const StorePrice(label: r'US$4.99'));
      expect((bundle.price, bundle.priceLabel, bundle.originalPrice, bundle.discountPercent), (null, r'US$4.99', null, null));
      expect(bundle.showsDiscount, isFalse);
    });

    test('바꿔도 상품 ID · 수량 · 그림 · 추천 표시는 그대로다', () {
      final bundle = hundred.withStorePrice(const StorePrice(label: '₩5,700', won: 5700));
      expect((bundle.productId, bundle.hearts, bundle.asset, bundle.isRecommended), (
        'heart_100',
        100,
        'assets/images/heart-bundle-100-v1.png',
        true,
      ));
    });
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
