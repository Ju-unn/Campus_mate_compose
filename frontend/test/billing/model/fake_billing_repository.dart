import 'dart:async';

import 'package:campus_mate/billing/model/billing_repository.dart';
import 'package:campus_mate/common/result.dart';

final String fakeAccountToken = 'a' * 64;

/// 애플 구매 창에 싣는 계정 표시(UUID) — 서버 apple_account_token 모양.
const String fakeAppleAccountToken = '3f2b8c1e-6a4d-4b7e-9c0a-1d2e3f4a5b6c';

const FirstPurchaseBonus fakeBonus = FirstPurchaseBonus(hearts: 50, minProductHearts: 100);

/// 뷰모델 · 화면 시험용 가짜 서버. 돌려줄 값을 필드로 바꿔 끼운다.
class FakeBillingRepository implements BillingRepository {
  Result<BillingStatus> status = Success(
    BillingStatus(accountToken: fakeAccountToken, appleAccountToken: fakeAppleAccountToken, bonus: fakeBonus),
  );

  /// verify 의 답(구글 · 애플 같은 모양). 기본은 첫 구매(보너스 50).
  Result<PurchaseOutcome> outcome = const Success(PurchaseGranted(hearts: 100, bonusHearts: 50, isNew: true));

  /// 구글 확인(/billing/google/verify)에 보낸 (상품, 구매 토큰).
  final List<(String, String)> verified = [];

  /// 애플 확인(/billing/apple/verify)에 보낸 (상품, 거래 번호).
  final List<(String, String)> appleVerified = [];
  int statusCount = 0;

  /// 채우면 verify 가 이 오류를 던진다(계약 밖 — Result 로 감싸지 못한 버그 흉내).
  Object? throwOnVerify;

  /// 채워 두면 verify 가 이것이 끝날 때까지 멈춘다 — "결제 확인 중" 모양 · 차례 확인용.
  Completer<void>? holdVerify;

  /// verify 가 지금 몇 개 동시에 돌고 있는지(차례대로 보내는지 본다).
  int running = 0;
  int maxRunning = 0;

  @override
  Future<Result<BillingStatus>> fetchStatus() async {
    statusCount++;
    return status;
  }

  @override
  Future<Result<PurchaseOutcome>> verifyGoogle(String productId, String purchaseToken) =>
      _answer(verified, productId, purchaseToken);

  @override
  Future<Result<PurchaseOutcome>> verifyApple(String productId, String transactionId) =>
      _answer(appleVerified, productId, transactionId);

  Future<Result<PurchaseOutcome>> _answer(List<(String, String)> sent, String productId, String token) async {
    sent.add((productId, token));
    running++;
    if (running > maxRunning) maxRunning = running;
    await holdVerify?.future;
    running--;
    final error = throwOnVerify;
    if (error != null) throw error;
    return outcome;
  }
}
