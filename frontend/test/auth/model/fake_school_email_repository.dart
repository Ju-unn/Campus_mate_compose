import 'package:campus_mate/auth/model/school_email_repository.dart';
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/model/verification_code.dart';
import 'package:campus_mate/common/result.dart';

/// 테스트 전용 [SchoolEmailRepository]. 기본은 셋 다 성공이고,
/// `next…Result` 를 지정해 실패를 흉내 낸다. [calls] 는 부른 순서(`requestCode` · `verifyCode` · `complete`)다.
class FakeSchoolEmailRepository implements SchoolEmailRepository {
  Result<void> nextRequestCodeResult = const Success(null);
  Result<String> nextVerifyCodeResult = const Success('temporary-access-token');
  Result<void> nextCompleteResult = const Success(null);
  final List<UniversityEmail> requestedEmails = [];
  final List<VerificationCode> verifiedCodes = [];
  final List<String> completedTokens = [];
  final List<String> calls = [];

  @override
  Future<Result<void>> requestCode(UniversityEmail email) {
    requestedEmails.add(email);
    calls.add('requestCode');
    // 실제 네트워크 호출처럼 마이크로태스크 이상의 지연을 흉내 내,
    // 위젯 테스트가 로딩 중 프레임을 pump() 로 관찰할 수 있게 한다.
    return Future.delayed(Duration.zero, () => nextRequestCodeResult);
  }

  @override
  Future<Result<String>> verifyCode(UniversityEmail email, VerificationCode code) {
    verifiedCodes.add(code);
    calls.add('verifyCode');
    return Future.delayed(Duration.zero, () => nextVerifyCodeResult);
  }

  @override
  Future<Result<void>> complete(String temporaryAccessToken) {
    completedTokens.add(temporaryAccessToken);
    calls.add('complete');
    return Future.delayed(Duration.zero, () => nextCompleteResult);
  }

  @override
  Future<void> discard() async {
    calls.add('discard');
  }
}
