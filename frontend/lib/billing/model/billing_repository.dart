import 'package:campus_mate/billing/model/billing_status.dart';
import 'package:campus_mate/common/result.dart';

/// 하트 구매 서버 창구(backend/app/billing/router.py · apple_router.py). 테스트는 Fake 로 덮는다.
abstract interface class BillingRepository {
  Future<Result<BillingStatus>> fetchStatus();

  /// 앱이 받은 구글 구매를 서버가 구글에 직접 물어 확인하고 하트를 준다. 실패 code 는 [ServerRejectedFailure] 에 실린다.
  Future<Result<PurchaseOutcome>> verifyGoogle(String productId, String purchaseToken);

  /// 앱이 받은 애플 거래(StoreKit 거래 번호)를 서버가 애플에 직접 물어 확인하고 하트를 준다. 응답 · 실패 code 는 구글과 같다
  /// (애플은 대기 202 가 없다).
  Future<Result<PurchaseOutcome>> verifyApple(String productId, String transactionId);
}
