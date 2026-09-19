import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/model/verification_code.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fake_auth_repository.dart';

void main() {
  test('기본값은 두 호출 모두 성공한다', () async {
    final repository = FakeAuthRepository();
    final email = UniversityEmail.tryParse('hong@snu.ac.kr')!;

    final requestResult = await repository.requestOtp(email);
    final verifyResult = await repository.verifyOtp(email, VerificationCode.tryParse('123456')!);

    expect(requestResult.when(onSuccess: (_) => true, onFailure: (_) => false), isTrue);
    expect(verifyResult.when(onSuccess: (_) => true, onFailure: (_) => false), isTrue);
  });

  test('nextRequestOtpResult를 지정하면 그 결과를 돌려준다', () async {
    final repository = FakeAuthRepository()..nextRequestOtpResult = const FailureResult(RateLimitedFailure());
    final email = UniversityEmail.tryParse('hong@snu.ac.kr')!;

    final result = await repository.requestOtp(email);

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<RateLimitedFailure>());
  });
}
