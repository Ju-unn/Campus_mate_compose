import 'package:campus_mate/billing/model/billing_repository.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';

/// [BillingRepository] 를 FastAPI 호출로 구현한다. 상태코드 분류는 `sendAuthorizedRequest` 가 한다(202 도 성공).
class HttpBillingRepository implements BillingRepository {
  const HttpBillingRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<BillingStatus>> fetchStatus() => _api.send('GET', '/billing/status', (body) {
        final json = body as Map<String, dynamic>;
        final bonus = json['first_purchase_bonus'] as Map<String, dynamic>?;
        return BillingStatus(
          accountToken: json['account_token'] as String,
          bonus: bonus == null
              ? null
              : FirstPurchaseBonus(hearts: bonus['hearts'] as int, minProductHearts: bonus['min_product_hearts'] as int),
        );
      });

  /// 결과 칸으로 가른다. 계약 밖의 result 는 던져서 [ApiClient.send] 가 알 수 없는 오류로 바꾸게 한다 — 지급으로 보지 않는다.
  @override
  Future<Result<PurchaseOutcome>> verifyGoogle(String productId, String purchaseToken) => _api.send(
        'POST',
        '/billing/google/verify',
        body: {'product_id': productId, 'purchase_token': purchaseToken},
        (body) {
          final json = body as Map<String, dynamic>;
          return switch (json['result']) {
            'pending' => const PurchasePendingAtStore(),
            'granted' || 'already_granted' => PurchaseGranted(
                hearts: json['hearts'] as int,
                bonusHearts: json['bonus_hearts'] as int,
                isNew: json['result'] == 'granted',
              ),
            final other => throw FormatException('verify result $other'),
          };
        },
      );
}
