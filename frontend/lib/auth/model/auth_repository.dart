import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/model/verification_code.dart';
import 'package:campus_mate/common/result.dart';

/// 대학 이메일 OTP 가입을 처리한다. 도메인 화이트리스트·재가입 제한 검사는
/// FastAPI Auth Hook(서버)이 가입 시점에 하므로, 여기서는 Supabase Auth
/// 호출만 감싼다(설계 §7.3, ERD.md §11-12).
abstract interface class AuthRepository {
  /// 인증코드 이메일 발송을 요청한다.
  Future<Result<void>> requestOtp(UniversityEmail email);

  /// 인증코드를 검증하고 성공하면 세션을 만든다.
  Future<Result<void>> verifyOtp(UniversityEmail email, VerificationCode code);
}
