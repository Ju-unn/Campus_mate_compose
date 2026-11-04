import 'package:campus_mate/billing/store/model/data/payment_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 이 기기의 스토어 — iOS 는 App Store, 그 밖은 구글 플레이. 구매 영역을 여는지는 heartPurchaseSupportedProvider 가 정한다.
/// dart:io 대신 [defaultTargetPlatform] 을 보는 건 시험에서 덮어쓸 수 있어서다(웹의 아이폰 사파리도 iOS 라 kIsWeb 을 먼저 본다).
final paymentStoreProvider = Provider<PaymentStore>(
  (ref) => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS ? PaymentStore.appStore : PaymentStore.googlePlay,
);
