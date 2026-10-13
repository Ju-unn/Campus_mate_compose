/// 스토어가 알려 준 가격. 원화면 [won] 이 있고, 다른 통화면 [label](스토어가 만든 글자)만 쓴다.
class StorePrice {
  const StorePrice({required this.label, this.won});

  final String label;
  final int? won;
}

/// 결제 창(또는 복구)에서 돌아온 것. 서버로 보낼 것은 [StorePurchased] 뿐이다.
/// 취소 · 실패는 플러그인이 상품 ID 를 비워 보낼 때가 있다(in_app_purchase_android 0.5.3) — 상품 ID 로 가르지 않는다.
sealed class StorePurchaseEvent {
  const StorePurchaseEvent(this.productId);

  final String productId;
}

/// 결제됨(또는 끝나지 않은 지난 결제를 다시 받음). [purchaseToken] 은 서버로 보낼 증거 — 구글은 구매 토큰, 애플은 거래 번호
/// (StoreKit 2 `Transaction.id`, 숫자 글자)다.
final class StorePurchased extends StorePurchaseEvent {
  const StorePurchased(super.productId, this.purchaseToken);

  final String purchaseToken;
}

/// 결제 수단 확인을 기다린다(느린 결제). 하트는 결제됨이 된 뒤에 준다.
final class StorePurchasePending extends StorePurchaseEvent {
  const StorePurchasePending(super.productId);
}

final class StorePurchaseCanceled extends StorePurchaseEvent {
  const StorePurchaseCanceled(super.productId);
}

final class StorePurchaseFailed extends StorePurchaseEvent {
  const StorePurchaseFailed(super.productId);
}
