import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/referral/model/referral_repository.dart';

/// [ReferralRepository]를 FastAPI 호출로 구현한다(backend/app/referral/router.py).
class HttpReferralRepository implements ReferralRepository {
  const HttpReferralRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<String>> redeem(String code) => _api.send(
        'POST',
        '/referral/redeem',
        (body) => (body as Map<String, dynamic>)['referrer_id'] as String,
        body: {'code': code},
      );

  @override
  Future<Result<String>> myCode() =>
      _api.send('GET', '/referral/my-code', (body) => (body as Map<String, dynamic>)['code'] as String);
}
