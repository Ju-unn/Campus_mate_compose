import 'package:campus_mate/auth/model/auth_repository.dart';
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/model/verification_code.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 코드 자체가 틀렸거나 기한이 지났을 때 GoTrue 가 주는 오류 코드(gotrue 2.27.2).
/// 그 밖의 403(`user_banned` 등)은 코드 문제가 아니므로 이 목록에 넣지 않는다.
const _wrongCodeCodes = <String>{'otp_expired', 'invalid_credentials'};

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
      // 틀린 코드와 만료된 코드를 GoTrue 가 같은 403 으로 돌려주지만 `code` 는 다르다.
      // 403 을 전부 "코드가 맞지 않아요" 로 보면 정지·차단된 계정(`user_banned`)까지
      // 코드 탓으로 보인다 — 코드 값을 보고 가른다.
      if (_wrongCodeCodes.contains(error.code)) {
        return const FailureResult(WrongCodeFailure());
      }
      // 코드를 안 주는 옛 GoTrue 응답도 있다 — 그때는 예전처럼 403 을 코드 문제로 본다.
      if (error.code == null && error.statusCode == '403') {
        return const FailureResult(WrongCodeFailure());
      }
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
