import 'package:campus_mate/common/result.dart';

/// 첫 구매 보너스. [hearts] 를 [minProductHearts] 하트 이상 상품에 더 준다(숫자는 서버가 내려 준다, 계획서 6-4).
class FirstPurchaseBonus {
  const FirstPurchaseBonus({required this.hearts, required this.minProductHearts});

  final int hearts;
  final int minProductHearts;

  bool appliesTo(int productHearts) => productHearts >= minProductHearts;
}

/// GET /billing/status. [accountToken] 은 구매 창에 싣는 계정 표시(64자 16진수 — 서버가 계정을 대조한다).
/// [bonus] 가 null 이면 이미 산 사람이다.
class BillingStatus {
  const BillingStatus({required this.accountToken, this.bonus});

  final String accountToken;
  final FirstPurchaseBonus? bonus;
}

/// 서버 확인 결과.
sealed class PurchaseOutcome {
  const PurchaseOutcome();
}

/// 하트가 들어갔다. [isNew] 가 false 면 이미 받은 결제를 다시 보낸 것이다(안내 없이 잔액만 새로).
final class PurchaseGranted extends PurchaseOutcome {
  const PurchaseGranted({required this.hearts, required this.bonusHearts, required this.isNew});

  final int hearts;
  final int bonusHearts;
  final bool isNew;
}

/// 구글이 아직 결제됨이 아니라고 한다(서버 202). 하트는 결제됨이 된 뒤에 다시 보내 받는다.
final class PurchasePendingAtStore extends PurchaseOutcome {
  const PurchasePendingAtStore();
}

/// 하트 구매 서버 창구(backend/app/billing/router.py). 테스트는 Fake 로 덮는다.
abstract interface class BillingRepository {
  Future<Result<BillingStatus>> fetchStatus();

  /// 앱이 받은 구글 구매를 서버가 구글에 직접 물어 확인하고 하트를 준다. 실패 code 는 [ServerRejectedFailure] 에 실린다.
  Future<Result<PurchaseOutcome>> verifyGoogle(String productId, String purchaseToken);
}
