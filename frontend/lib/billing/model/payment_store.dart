import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 하트를 사는 스토어. 화면에 스토어 이름이 들어가는 결제 안내 두 줄은 여기 둔다(결제 불가 배너 설명은 HeartPurchaseNotice).
/// pen 결제 안내(`bBjRD`)는 구글판만 있다 — App Store 판은 같은 꼴에 이름만 바꾼 것이라 pen 후속(약속을 더하지 않는 글자).
enum PaymentStore {
  /// pen `bBjRD` 두 줄.
  googlePlay(paymentLine: '결제는 구글 플레이로 처리돼요', refundLine: '결제 취소 · 환불은 구글 플레이 환불 절차를 따라요'),

  /// pen 에 없다(후속). 애플은 환불을 애플이 정하므로 우리 쪽 기한 · 조건을 말하지 않는다.
  appStore(paymentLine: '결제는 App Store로 처리돼요', refundLine: '결제 취소 · 환불은 App Store 환불 절차를 따라요');

  const PaymentStore({required this.paymentLine, required this.refundLine});

  final String paymentLine;
  final String refundLine;
}

/// 이 기기의 스토어 — iOS 는 App Store, 그 밖은 구글 플레이. 구매 영역을 여는지는 heartPurchaseSupportedProvider 가 정한다.
/// dart:io 대신 [defaultTargetPlatform] 을 보는 건 시험에서 덮어쓸 수 있어서다(웹의 아이폰 사파리도 iOS 라 kIsWeb 을 먼저 본다).
final paymentStoreProvider = Provider<PaymentStore>(
  (ref) => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS ? PaymentStore.appStore : PaymentStore.googlePlay,
);
