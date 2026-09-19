import 'package:campus_mate/auth/model/auth_repository.dart';
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/model/verification_code.dart';
import 'package:campus_mate/common/result.dart';

/// 테스트 전용 [AuthRepository]. 기본은 항상 성공이고,
/// `nextRequestOtpResult`·`nextVerifyOtpResult` 를 지정해 실패를 흉내 낼 수 있다.
class FakeAuthRepository implements AuthRepository {
  Result<void> nextRequestOtpResult = const Success(null);
  Result<void> nextVerifyOtpResult = const Success(null);
  final List<UniversityEmail> requestedEmails = [];
  final List<VerificationCode> verifiedCodes = [];

  @override
  Future<Result<void>> requestOtp(UniversityEmail email) {
    requestedEmails.add(email);
    // 실제 네트워크 호출처럼 마이크로태스크 이상의 지연을 흉내 내,
    // 위젯 테스트가 로딩 중 프레임을 pump() 로 관찰할 수 있게 한다.
    return Future.delayed(Duration.zero, () => nextRequestOtpResult);
  }

  @override
  Future<Result<void>> verifyOtp(UniversityEmail email, VerificationCode code) {
    verifiedCodes.add(code);
    return Future.delayed(Duration.zero, () => nextVerifyOtpResult);
  }
}
