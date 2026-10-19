// 임시 진단 — heart_price_diag.dart 와 같이 지운다.
import 'package:campus_mate/billing/model/heart_price_diag.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

void main() {
  test('상품마다 한 줄, 못 찾은 상품은 못 찾음, 맨 위는 스토어 국가', () {
    final text = heartPriceDiagText(
      productIds: {'heart_50', 'heart_100'},
      details: {
        'heart_50': ProductDetails(
          id: 'heart_50',
          title: '',
          description: '',
          price: r'$2.99',
          rawPrice: 2.99,
          currencyCode: 'USD',
          currencySymbol: r'$',
        ),
      },
      country: 'KOR',
    );

    expect(text.split('\n'), [
      '스토어 국가 KOR',
      r'heart_50 | 종류 ProductDetails | 통화 USD | 기호 $ | 글자 $2.99 | 숫자 2.99',
      'heart_100 | 못 찾음',
    ]);
  });
}
