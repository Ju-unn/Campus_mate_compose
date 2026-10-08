import 'package:campus_mate/auth/model/school_email_repository.dart';
import 'package:campus_mate/auth/model/temporary_auth_connection.dart';
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/model/verification_code.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 코드 자체가 틀렸거나 기한이 지났을 때 GoTrue 가 주는 오류 코드(gotrue 2.27.2).
/// 그 밖의 403(`user_banned` 등)은 코드 문제가 아니므로 이 목록에 넣지 않는다.
const _wrongCodeCodes = <String>{'otp_expired', 'invalid_credentials'};

/// 서버(backend `app/core/errors.py` `CODE_*`)가 POST /school-email/verify 오류의 `code` 에 싣는 값.
const _codeAlreadyVerified = 'SCHOOL_EMAIL_ALREADY_VERIFIED';
const _codeNotConfirmed = 'SCHOOL_EMAIL_NOT_CONFIRMED';
const _codesRejected = {'SCHOOL_EMAIL_DOMAIN_NOT_ALLOWED', 'SCHOOL_EMAIL_REJOIN_BLOCKED'};
const _codeAuthUnavailable = 'AUTH_UNAVAILABLE';

/// ponytail: code 가 없는 옛 서버 호환용 문구 비교 — 서버 배포 뒤 제거 가능. 글자까지 같아야 한다.
const _alreadyVerified = '이미 학교 메일 인증이 끝났어요'; // SCHOOL_EMAIL_ALREADY_VERIFIED
const _notConfirmed = '학교 메일 인증이 끝나지 않았어요'; // SCHOOL_EMAIL_NOT_CONFIRMED

/// 등록되지 않은 학교 메일. 가입 직전 훅(02)과 서버(03)가 이제 같은 문구다.
const unknownSchoolEmailMessage = '등록되지 않은 학교 메일이에요';

/// 422 거절 문구(옛 서버 호환). 재가입 제한은 훅("…이메일이에요")과 서버("…메일이에요") 글자가 달라 둘 다 둔다.
const _rejectedMessages = {
  unknownSchoolEmailMessage,
  '허용되지 않은 학교 이메일이에요', // 옛 훅 문구, 호환용
  '재가입이 제한된 메일이에요', // 서버 SCHOOL_EMAIL_BLOCKED
  '재가입이 제한된 이메일이에요', // 훅 HOOK_BLOCKED
};

/// [SchoolEmailRepository]를 임시 Supabase 연결 + FastAPI 로 구현한다.
class SupabaseSchoolEmailRepository implements SchoolEmailRepository {
  SupabaseSchoolEmailRepository(this._api, this._connection);

  /// 메인(소셜) 연결의 토큰을 붙이는 서버 클라이언트.
  final ApiClient _api;

  /// 학교 메일 OTP 전용 임시 연결. 메인 연결이 아니다.
  final TemporaryAuthConnection _connection;

  @override
  Future<Result<void>> requestCode(UniversityEmail email) async {
    try {
      await _connection.open().signInWithOtp(email: email.toRequestValue(), shouldCreateUser: true);
      return const Success(null);
    } on AuthException catch (error) {
      return FailureResult(_toRequestFailure(error));
    } on Exception {
      return const FailureResult(CodeNotSentFailure());
    }
  }

  @override
  Future<Result<String>> verifyCode(UniversityEmail email, VerificationCode code) async {
    try {
      final response = await _connection.open().verifyOTP(
        email: email.toRequestValue(),
        token: code.toRequestValue(),
        type: OtpType.email,
      );
      return _toTemporaryToken(response.session);
    } on AuthException catch (error) {
      return FailureResult(_toVerifyFailure(error));
    } on Exception {
      return const FailureResult(SchoolEmailIncompleteFailure());
    }
  }

  @override
  Future<Result<void>> complete(String temporaryAccessToken) async {
    final result = await _api.send(
      'POST',
      '/school-email/verify',
      (_) {},
      body: {'temp_access_token': temporaryAccessToken},
    );
    // null = 성공(이미 인증 포함).
    final failure = result.when<Failure?>(onSuccess: (_) => null, onFailure: _toCompleteFailure);
    if (failure == null || endsSchoolEmailAttempt(failure)) {
      await _connection.close();
    }
    return failure == null ? const Success(null) : FailureResult(failure);
  }

  @override
  Future<void> discard() => _connection.close();

  /// 429 는 보내기 한도(같은 메일에 60초 안에 다시 보내기 포함), 422 는 가입 직전 훅의 거절(등록되지 않은 학교 ·
  /// 재가입 제한 — 서버 문구를 그대로)이다(backend `auth_hooks/schemas.py` 의 422). 나머지는 가르지 않는다.
  Failure _toRequestFailure(AuthException error) {
    return switch (error.statusCode) {
      '429' => const RateLimitedFailure(),
      '422' => SignUpRejectedFailure(error.message),
      _ => const CodeNotSentFailure(),
    };
  }

  Result<String> _toTemporaryToken(Session? session) {
    if (session == null) {
      return const FailureResult(SchoolEmailIncompleteFailure());
    }
    return Success(session.accessToken);
  }

  /// 틀린 코드와 만료된 코드를 GoTrue 가 같은 403 으로 돌려주지만 `code` 는 다르다 — 코드 값을 보고 가른다.
  /// 코드를 안 주는 옛 GoTrue 응답(403)은 예전처럼 코드 문제로 본다.
  Failure _toVerifyFailure(AuthException error) {
    final isWrongCode = _wrongCodeCodes.contains(error.code) || (error.code == null && error.statusCode == '403');
    if (isWrongCode) {
      return const WrongCodeFailure();
    }
    if (error.statusCode == '429') {
      return const RateLimitedFailure();
    }
    return const SchoolEmailIncompleteFailure();
  }

  /// 서버가 잠깐 못 받음 · 네트워크 → 다시 하라는 문구. 서버 거절은 code(없으면 문구)로 가른다.
  /// 409(다른 소셜 계정, http_send 가 이미 가름) · 세션 · 정지 같은 나머지는 그대로 올린다.
  Failure? _toCompleteFailure(Failure failure) {
    if (failure is ServerRejectedFailure) {
      return failure.hasAnyCode() ? _byCode(failure) : _byMessage(failure);
    }
    final isTransient = failure is NetworkFailure || failure is ServerUnavailableFailure || failure is UnknownFailure;
    return isTransient ? const SchoolEmailIncompleteFailure() : failure;
  }

  /// null = 이미 인증(성공과 같이). 계약에 없는 code(SOCIAL_ONLY · PROFILE_NOT_FOUND)는 서버 문구 그대로.
  Failure? _byCode(ServerRejectedFailure failure) {
    if (failure.hasCode(_codeAlreadyVerified)) {
      return null;
    }
    if (failure.hasCode(_codeNotConfirmed)) {
      return const SchoolEmailNotConfirmedFailure();
    }
    if (_codesRejected.any(failure.hasCode)) {
      return SchoolEmailRejectedFailure(failure.toDisplayMessage());
    }
    return failure.hasCode(_codeAuthUnavailable) ? const SchoolEmailIncompleteFailure() : failure;
  }

  /// ponytail: code 없는 옛 서버 호환 — 서버 배포 뒤 제거 가능.
  Failure? _byMessage(ServerRejectedFailure failure) {
    final message = failure.toDisplayMessage();
    if (message == _alreadyVerified) {
      return null;
    }
    if (message == _notConfirmed) {
      return const SchoolEmailNotConfirmedFailure();
    }
    return _rejectedMessages.contains(message) ? SchoolEmailRejectedFailure(message) : failure;
  }
}
