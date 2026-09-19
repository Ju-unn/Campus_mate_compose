import 'package:campus_mate/auth/model/auth_repository.dart';
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/model/verification_code.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// [AuthRepository]를 Supabase Auth로 구현한다.
class SupabaseAuthRepository implements AuthRepository {
  const SupabaseAuthRepository(this._auth);

  final GoTrueClient _auth;

  @override
  Future<Result<void>> requestOtp(UniversityEmail email) async {
    try {
      await _auth.signInWithOtp(email: email.toRequestValue());
      return const Success(null);
    } on AuthException catch (error) {
      return FailureResult(_toFailure(error));
    }
  }

  @override
  Future<Result<void>> verifyOtp(UniversityEmail email, VerificationCode code) async {
    try {
      await _auth.verifyOTP(
        email: email.toRequestValue(),
        token: code.toRequestValue(),
        type: OtpType.email,
      );
      return const Success(null);
    } on AuthException catch (error) {
      return FailureResult(_toFailure(error));
    }
  }

  /// 429는 재전송·요청 한도, 그 외 Auth Hook 거부(422)는 서버 메시지를
  /// 그대로 보여준다. 나머지는 사용자에게 내부 사정을 노출하지 않는다.
  Failure _toFailure(AuthException error) {
    if (error.statusCode == '429') {
      return const RateLimitedFailure();
    }
    if (error.statusCode == '422') {
      return SignUpRejectedFailure(error.message);
    }
    return const UnknownFailure();
  }
}
