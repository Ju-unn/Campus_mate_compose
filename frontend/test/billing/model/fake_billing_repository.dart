import 'dart:async';

import 'package:campus_mate/billing/model/billing_repository.dart';
import 'package:campus_mate/common/result.dart';

final String fakeAccountToken = 'a' * 64;

const FirstPurchaseBonus fakeBonus = FirstPurchaseBonus(hearts: 50, minProductHearts: 100);

/// 뷰모델 · 화면 시험용 가짜 서버. 돌려줄 값을 필드로 바꿔 끼운다.
class FakeBillingRepository implements BillingRepository {
  Result<BillingStatus> status = Success(BillingStatus(accountToken: fakeAccountToken, bonus: fakeBonus));

  /// verify 의 답. 기본은 첫 구매(보너스 50).
  Result<PurchaseOutcome> outcome = const Success(PurchaseGranted(hearts: 100, bonusHearts: 50, isNew: true));

  final List<(String, String)> verified = [];
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
  Future<Result<PurchaseOutcome>> verifyGoogle(String productId, String purchaseToken) async {
    verified.add((productId, purchaseToken));
    running++;
    if (running > maxRunning) maxRunning = running;
    await holdVerify?.future;
    running--;
    final error = throwOnVerify;
    if (error != null) throw error;
    return outcome;
  }
}
