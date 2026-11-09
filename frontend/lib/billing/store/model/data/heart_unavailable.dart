/// 하트 상점을 못 여는 원인 셋(빨간 배너 `YOhKL` 은 하나, 설명 글자만 원인마다 다르다). 아이폰에서 사용자가 화면만 보고 어느 경우인지 알게 한다.
enum HeartUnavailableReason {
  /// 이 기기에서 스토어 결제를 쓸 수 없음(StoreKit isAvailable false — 앱 내 구입 제한 등).
  storeUnusable,

  /// 스토어가 상품을 하나도 안 줌(가격 0개 — 상품 미등록 · 준비 중 · 조회 오류).
  noProducts,

  /// 서버 /billing/status 를 못 읽었거나 이 스토어의 계정 표시가 없음.
  serverStatus,
}

/// 결제 불가 한 번의 사정 — 원인과 못 찾은 상품 개수.
final class HeartUnavailable {
  const HeartUnavailable(this.reason, {this.missingProducts = 0});

  final HeartUnavailableReason reason;
  final int missingProducts;

  // App Store 배너 설명 글자는 view 쪽 확장(heart_store_text.dart), 로그 한 줄은 뷰모델의 debugPrint 가 만든다.
}
