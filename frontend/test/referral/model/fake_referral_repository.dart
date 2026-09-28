import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/referral/model/referral_repository.dart';

/// 테스트 전용 [ReferralRepository]. 기본은 코드 입력 성공(추천인 id)과 내 코드 조회 성공이다.
class FakeReferralRepository implements ReferralRepository {
  Result<String> nextRedeem = const Success('22222222-2222-2222-2222-222222222222');
  Result<String> nextMyCode = const Success('K7QMX2');
  final redeemedCodes = <String>[];

  @override
  Future<Result<String>> redeem(String code) async {
    redeemedCodes.add(code);
    return nextRedeem;
  }

  @override
  Future<Result<String>> myCode() async => nextMyCode;
}
