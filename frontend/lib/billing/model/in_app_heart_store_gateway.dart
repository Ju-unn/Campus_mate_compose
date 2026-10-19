import 'dart:async';

import 'package:campus_mate/billing/model/heart_store_gateway.dart';
import 'package:campus_mate/billing/model/store_purchase.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// 앱 진입점(main.dart)이 끼우는 진짜 창구 — 안드로이드는 구글 플레이, iOS 는 App Store. 그 밖(웹 · 데스크톱)은 null 이라
/// provider 기본값(아무것도 하지 않는 창구)이 그대로다. 플러그인은 창구를 고른 뒤에만 만든다.
HeartStoreGateway? platformHeartStoreGateway(InAppPurchase Function() plugin) {
  if (kIsWeb) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => InAppHeartStoreGateway(plugin()),
    TargetPlatform.iOS => AppStoreHeartStoreGateway(plugin()),
    _ => null,
  };
}

/// 두 스토어가 같이 쓰는 부분 — 쓸 수 있는지 · 가격 · 결제 창에 넘길 상품 정보.
mixin _StoreCatalog implements HeartStoreGateway {
  InAppPurchase get _iap;

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
    // 결제 불가 배너의 원인을 가르는 단서 — 스토어가 모른다고 한 상품 · 스토어 오류 코드.
    if (response.notFoundIDs.isNotEmpty || response.error != null) {
      final error = response.error;
      debugPrint(
        '하트 상품 조회: 찾은 상품 ${response.productDetails.length}개 · 못 찾은 상품 ${response.notFoundIDs}'
        '${error == null ? '' : ' · 스토어 오류 ${error.code}'}',
      );
    }
    return {for (final details in response.productDetails) details.id: _priceOf(details)};
  }

  StorePrice _priceOf(ProductDetails details) =>
      StorePrice(label: details.price, won: details.currencyCode == _won ? details.rawPrice.round() : null);
}

/// [HeartStoreGateway] 의 구글 플레이 구현(in_app_purchase 3.3.1 · in_app_purchase_android 0.5.3).
/// 안드로이드는 completePurchase 를 부르지 않는다 — 서버가 지급 뒤 소비하고, 소비가 확인 처리를 겸한다.
class InAppHeartStoreGateway with _StoreCatalog implements HeartStoreGateway {
  InAppHeartStoreGateway(this._iap);

  @override
  final InAppPurchase _iap;

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

  /// 앱이 끝낼 것이 없다 — 서버가 지급 뒤 구글에 소비를 부른다(그 전에 끝내면 서버 확인 전에 구매가 사라진다).
  @override
  Future<void> finish(String purchaseToken) async {}

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

/// [HeartStoreGateway] 의 App Store 구현(StoreKit 2 — in_app_purchase_storekit 0.4.13+2, 최소 iOS 15.5 라 StoreKit 2 가 기본).
/// 구글과 다른 점(플러그인 소스와 애플 문서로 확인):
/// - 서버로 보내는 것은 거래 번호 `purchaseID`(StoreKit 2 `Transaction.id` 의 10진수 글자)다. `serverVerificationData` 는 서명된
///   거래(JWS)라 보내지 않는다 — 서버가 거래 번호로 애플에 직접 묻는다.
/// - StoreKit 2 는 거래를 스스로 끝내지 않는다. 서버가 지급했다고 답한 뒤에만 [finish] 가 completePurchase(finish)를 부른다.
///   끝내지 않은 거래는 다음 앱 시작 때 StoreKit 이 한 번 다시 준다(Transaction.updates) — 구글의 "소비 안 된 구매 복구" 자리.
/// - 소모품은 restorePurchases(Transaction.currentEntitlements)에 나오지 않는다 — [recover] 는 받아 두고 아직 끝내지 않은 거래를
///   다시 흘린다.
// ponytail: 다른 기기 · 이 앱이 못 들은 끝내지 않은 거래는 다음 앱 시작을 기다린다. 바로 받아야 하면 Transaction.unfinished
// (in_app_purchase_storekit 의 SK2Transaction.unfinishedTransactions)를 쓰되, 그 패키지를 직접 의존성으로 올려야 한다.
class AppStoreHeartStoreGateway with _StoreCatalog implements HeartStoreGateway {
  /// 만들자마자(앱 시작) 듣는다 — StoreKit 은 끝내지 않은 거래를 앱 시작 직후 한 번만 준다. 뷰모델(관문 뒤)이 아직 듣지 않아도
  /// [_unfinished] 에 남아 [recover] 가 다시 흘린다. 창구는 앱이 끝날 때까지 하나라 이 구독을 끊지 않는다.
  AppStoreHeartStoreGateway(this._iap) {
    _iap.purchaseStream.listen(_relay);
  }

  @override
  final InAppPurchase _iap;

  /// 서버 지급 전이라 끝내지 않은 거래 — 거래 번호 → 플러그인 객체([finish] 에 그대로 넘긴다).
  final Map<String, PurchaseDetails> _unfinished = {};

  final StreamController<List<StorePurchaseEvent>> _events = StreamController<List<StorePurchaseEvent>>.broadcast();

  /// appAccountToken 은 UUID 여야 한다 — 아니면 플러그인이 말없이 빼고 결제해 서버가 계정을 가리지 못한다.
  static final RegExp _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

  @override
  Stream<List<StorePurchaseEvent>> get events => _events.stream;

  void _relay(List<PurchaseDetails> purchases) {
    _unfinished.addAll({for (final purchase in purchases) ?_transactionIdOf(purchase): purchase});
    _events.add(purchases.map(_toEvent).toList());
  }

  @override
  Future<bool> buy(String productId, String accountToken) async {
    final details = _details[productId];
    if (details == null || !_uuid.hasMatch(accountToken)) return false;
    try {
      // autoConsume 은 넘기지 않는다 — 안드로이드 옵션이라 iOS 플러그인은 기본값(true)만 받고(assert) 쓰지도 않는다.
      // 거래를 끝내는 곳은 [finish] 뿐이다. 계정 표시는 applicationUserName → StoreKit appAccountToken.
      return await _iap.buyConsumable(
        purchaseParam: PurchaseParam(productDetails: details, applicationUserName: accountToken),
      );
    } on Exception {
      // 같은 상품의 끝내지 않은 거래가 있으면 플러그인이 던진다(storekit_duplicate_product_object) — 뷰모델이 실패 안내 뒤
      // 복구해 그 거래를 다시 보낸다.
      return false;
    }
  }

  @override
  Future<void> recover() async {
    if (_unfinished.isNotEmpty) _events.add(_unfinished.values.map(_toEvent).toList());
  }

  @override
  Future<void> finish(String purchaseToken) async {
    final purchase = _unfinished.remove(purchaseToken);
    if (purchase == null) return;
    try {
      await _iap.completePurchase(purchase);
    } on Exception {
      // 못 끝낸 거래는 다음 앱 시작 때 StoreKit 이 다시 준다 — 서버는 같은 거래에 하트를 두 번 주지 않는다(already_granted).
      return;
    }
  }

  /// 결제됨인데 거래 번호가 없으면(플러그인은 대기 · 취소에 거래 번호 0 → null 을 준다) 서버로 보낼 것이 없으니 실패로 둔다.
  StorePurchaseEvent _toEvent(PurchaseDetails purchase) => switch ((purchase.status, _transactionIdOf(purchase))) {
        (_, final id?) => StorePurchased(purchase.productID, id),
        (PurchaseStatus.pending, _) => StorePurchasePending(purchase.productID),
        (PurchaseStatus.canceled, _) => StorePurchaseCanceled(purchase.productID),
        _ => StorePurchaseFailed(purchase.productID),
      };

  static String? _transactionIdOf(PurchaseDetails purchase) {
    final paid = purchase.status == PurchaseStatus.purchased || purchase.status == PurchaseStatus.restored;
    final id = purchase.purchaseID;
    return paid && id != null && id.isNotEmpty ? id : null;
  }
}
