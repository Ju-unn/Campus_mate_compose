import 'package:campus_mate/billing/store/model/data/payment_store.dart';

/// 첫 구매 보너스. [hearts] 를 [minProductHearts] 하트 이상 상품에 더 준다(숫자는 서버가 내려 준다, 계획서 6-4).
class FirstPurchaseBonus {
  const FirstPurchaseBonus({required this.hearts, required this.minProductHearts});

  final int hearts;
  final int minProductHearts;

  bool appliesTo(int productHearts) => productHearts >= minProductHearts;
}

/// GET /billing/status. 계정 표시는 구매 창에 실려 서버가 계정을 대조한다 — 구글은 [accountToken](64자 16진수 →
/// obfuscatedAccountId), 애플은 [appleAccountToken](UUID → appAccountToken). [bonus] 가 null 이면 이미 산 사람이다.
class BillingStatus {
  const BillingStatus({required this.accountToken, this.appleAccountToken, this.bonus});

  final String accountToken;

  /// 이 칸을 아직 주지 않는 서버(애플 결제 배포 전)면 null — iOS 는 사지 못한다(구글 표시로 대신 사지 않는다).
  final String? appleAccountToken;
  final FirstPurchaseBonus? bonus;

  /// [store] 의 구매 창에 실을 계정 표시.
  String? accountTokenFor(PaymentStore store) => switch (store) {
        PaymentStore.googlePlay => accountToken,
        PaymentStore.appStore => appleAccountToken,
      };
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
