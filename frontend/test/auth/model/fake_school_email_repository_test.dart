import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/model/verification_code.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fake_school_email_repository.dart';

void main() {
  final email = UniversityEmail.tryParse('hong@snu.ac.kr')!;

  test('기본값은 셋 다 성공하고 부른 순서를 남긴다', () async {
    final repository = FakeSchoolEmailRepository();

    final request = await repository.requestCode(email);
    final verify = await repository.verifyCode(email, VerificationCode.tryParse('123456')!);
    final complete = await repository.complete('temporary-access-token');

    expect(request.when(onSuccess: (_) => true, onFailure: (_) => false), isTrue);
    expect(verify.when(onSuccess: (token) => token, onFailure: (_) => null), 'temporary-access-token');
    expect(complete.when(onSuccess: (_) => true, onFailure: (_) => false), isTrue);
    expect(repository.calls, ['requestCode', 'verifyCode', 'complete']);
    expect(repository.completedTokens, ['temporary-access-token']);
  });

  test('discard 도 부른 순서에 남긴다', () async {
    final repository = FakeSchoolEmailRepository();

    await repository.discard();

    expect(repository.calls, ['discard']);
  });

  test('next…Result 를 지정하면 그 결과를 돌려준다', () async {
    final repository = FakeSchoolEmailRepository()
      ..nextRequestCodeResult = const FailureResult(RateLimitedFailure())
      ..nextCompleteResult = const FailureResult(SchoolEmailIncompleteFailure());

    final request = await repository.requestCode(email);
    final complete = await repository.complete('token');

    expect(request.when(onSuccess: (_) => null, onFailure: (f) => f), isA<RateLimitedFailure>());
    expect(complete.when(onSuccess: (_) => null, onFailure: (f) => f), isA<SchoolEmailIncompleteFailure>());
  });
}
