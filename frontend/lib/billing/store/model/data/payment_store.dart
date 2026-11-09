/// 하트를 사는 스토어. 스토어 이름이 들어가는 결제 안내 두 줄의 글자는 view 쪽 확장(heart_store_text.dart)이 정한다.
/// pen 결제 안내(`bBjRD`)는 구글판만 있다 — App Store 판은 같은 꼴에 이름만 바꾼 것이라 pen 후속(약속을 더하지 않는 글자).
enum PaymentStore {
  /// pen `bBjRD` 두 줄.
  googlePlay,

  /// pen 에 없다(후속). 애플은 환불을 애플이 정하므로 우리 쪽 기한 · 조건을 말하지 않는다.
  appStore,
}
