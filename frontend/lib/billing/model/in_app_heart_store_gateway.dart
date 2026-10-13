import 'package:campus_mate/billing/model/heart_store_gateway.dart';
import 'package:campus_mate/billing/model/store_purchase.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// [HeartStoreGateway] 의 구글 플레이 구현(in_app_purchase 3.3.1 · in_app_purchase_android 0.5.3). iOS 는 아직 쓰지 않는다(계획서 7-1).
/// 안드로이드는 completePurchase 를 부르지 않는다 — 서버가 지급 뒤 소비하고, 소비가 확인 처리를 겸한다.
class InAppHeartStoreGateway implements HeartStoreGateway {
  InAppHeartStoreGateway(this._iap);

  final InAppPurchase _iap;

  /// 결제 창을 열 때 필요한 스토어 상품 정보. [loadPrices] 가 채운다.
  final Map<String, ProductDetails> _details = {};

  static const String _won = 'KRW';

  @override
  Future<bool> isAvailable() async {
    try {
      return await _iap.isAvailable();
    } on Exception {
      return false;
    }
  }

  @override
  Future<Map<String, StorePrice>> loadPrices(Set<String> productIds) async {
    final response = await _iap.queryProductDetails(productIds);
    for (final details in response.productDetails) {
      _details[details.id] = details;
    }
    return {for (final details in response.productDetails) details.id: _priceOf(details)};
  }

  StorePrice _priceOf(ProductDetails details) =>
      StorePrice(label: details.price, won: details.currencyCode == _won ? details.rawPrice.round() : null);

  @override
  Stream<List<StorePurchaseEvent>> get events => _iap.purchaseStream.map((list) => list.map(_toEvent).toList());

  @override
  Future<bool> buy(String productId, String accountToken) async {
    final details = _details[productId];
    if (details == null) return false;
    try {
      // autoConsume 을 끈다 — 켜면 플러그인이 purchaseStream 에 내보내기 전에 소비해 서버 확인 전에 구매가 끝난다.
      // 계정 표시는 applicationUserName → 안드로이드 obfuscatedAccountId 로 실려 서버가 계정을 대조한다.
      return await _iap.buyConsumable(
        purchaseParam: PurchaseParam(productDetails: details, applicationUserName: accountToken),
        autoConsume: false,
      );
    } on Exception {
      return false;
    }
  }

  /// 안드로이드 restorePurchases = 소비 안 된 구매를 모두 `restored` 로 다시 흘린다(대기 중인 것도 restored 로 온다 —
  /// 서버가 202 로 가른다). 조회 실패는 던지는데, 다음 복구 때 다시 하면 되니 삼킨다.
  @override
  Future<void> recover() async {
    try {
      await _iap.restorePurchases();
    } on Exception {
      return;
    }
  }

  /// 결제가 OK 인데 구매 목록이 비면 플러그인은 상품 · 토큰이 빈 purchased 를 보낸다 — 서버로 보낼 것이 없으니 실패로 둔다
  /// (화면은 실패 안내 뒤 복구해 실제 구매가 있으면 이어서 받는다).
  StorePurchaseEvent _toEvent(PurchaseDetails purchase) {
    final token = purchase.verificationData.serverVerificationData;
    return switch (purchase.status) {
      PurchaseStatus.purchased || PurchaseStatus.restored when token.isNotEmpty => StorePurchased(purchase.productID, token),
      PurchaseStatus.purchased || PurchaseStatus.restored || PurchaseStatus.error => StorePurchaseFailed(purchase.productID),
      PurchaseStatus.pending => StorePurchasePending(purchase.productID),
      PurchaseStatus.canceled => StorePurchaseCanceled(purchase.productID),
    };
  }
}
