// 임시 진단 — TestFlight 에서 하트 가격이 달러로 보이는 원인 확인용. main 에 합치지 않는다. 지울 때는 이 파일과
// 이 파일을 import 하는 두 곳(in_app_heart_store_gateway.dart · heart_store_screen.dart)의 "임시 진단" 줄을 지운다.
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// 임시 진단 — 하트 상점 맨 아래 회색 글씨로 보여 줄 줄들. 가격을 읽을 때마다 새로 채운다.
final ValueNotifier<String> heartPriceDiag = ValueNotifier<String>('');

/// 임시 진단 — 가격 조회 응답과 스토어프런트 국가 코드(iOS StoreKit2 Storefront · 안드로이드 결제 설정)를 [heartPriceDiag] 에 쓴다.
/// 국가 코드를 못 읽어도 가격 줄은 남긴다.
Future<void> recordHeartPriceDiag(InAppPurchase iap, Set<String> productIds, ProductDetailsResponse response) async {
  String country;
  try {
    country = await iap.countryCode();
  } catch (e) {
    country = '읽기 실패(${e.runtimeType})';
  }
  heartPriceDiag.value = heartPriceDiagText(
    productIds: productIds,
    details: {for (final d in response.productDetails) d.id: d},
    country: country,
    errorCode: response.error?.code,
  );
}

/// 임시 진단 — 스토어가 준 상품 정보를 상품마다 한 줄로, 맨 위에 스토어프런트 국가 코드 · 스토어 오류.
String heartPriceDiagText({
  required Set<String> productIds,
  required Map<String, ProductDetails> details,
  required String country,
  String? errorCode,
}) =>
    [
      '스토어 국가 $country${errorCode == null ? '' : ' | 스토어 오류 $errorCode'}',
      for (final id in productIds)
        switch (details[id]) {
          final d? => '$id | 종류 ${d.runtimeType} | 통화 ${d.currencyCode} | 기호 ${d.currencySymbol}'
              ' | 글자 ${d.price} | 숫자 ${d.rawPrice}',
          null => '$id | 못 찾음',
        },
    ].join('\n');
