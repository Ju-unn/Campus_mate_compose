import 'package:campus_mate/billing/model/in_app_heart_store_gateway.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mocktail/mocktail.dart';

class _MockInAppPurchase extends Mock implements InAppPurchase {}

void main() {
  late _MockInAppPurchase iap;
  late List<String?> logs;
  late DebugPrintCallback originalDebugPrint;

  setUp(() {
    iap = _MockInAppPurchase();
    when(() => iap.purchaseStream).thenAnswer((_) => const Stream.empty());
    logs = [];
    originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message);
    addTearDown(() => debugPrint = originalDebugPrint);
  });

  test('스토어가 상품을 못 찾으면 못 찾은 상품 ID 와 스토어 오류 코드를 로그에 남긴다 — 결제 불가 원인을 가르는 단서', () async {
    when(() => iap.queryProductDetails(any())).thenAnswer(
      (_) async => ProductDetailsResponse(
        productDetails: const [],
        notFoundIDs: const ['heart_50', 'heart_100'],
        error: IAPError(source: 'app_store', code: 'storekit_getproductserror', message: 'x'),
      ),
    );

    final prices = await AppStoreHeartStoreGateway(iap).loadPrices({'heart_50', 'heart_100'});

    expect(prices, isEmpty);
    expect(logs, ['하트 상품 조회: 찾은 상품 0개 · 못 찾은 상품 [heart_50, heart_100] · 스토어 오류 storekit_getproductserror']);
  });

  test('다 찾았으면 로그가 없다', () async {
    when(() => iap.queryProductDetails(any())).thenAnswer(
      (_) async => ProductDetailsResponse(
        productDetails: [
          ProductDetails(id: 'heart_100', title: 't', description: '', price: '₩5,700', rawPrice: 5700, currencyCode: 'KRW'),
        ],
        notFoundIDs: const [],
      ),
    );

    await AppStoreHeartStoreGateway(iap).loadPrices({'heart_100'});

    expect(logs, isEmpty);
  });
}
