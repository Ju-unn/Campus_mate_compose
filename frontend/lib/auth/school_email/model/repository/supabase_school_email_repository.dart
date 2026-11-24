import 'package:campus_mate/auth/school_email/model/data/school_email_attempt.dart';
import 'package:campus_mate/auth/school_email/model/data/university_email.dart';
import 'package:campus_mate/auth/school_email/model/data/verification_code.dart';
import 'package:campus_mate/auth/school_email/model/repository/school_email_repository.dart';
import 'package:campus_mate/auth/school_email/model/repository/temporary_auth_connection.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/core/http/http_send.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 코드 자체가 틀렸거나 기한이 지났을 때 GoTrue 가 주는 오류 코드(gotrue 2.27.2).
/// 그 밖의 403(`user_banned` 등)은 코드 문제가 아니므로 이 목록에 넣지 않는다.
const _wrongCodeCodes = <String>{'otp_expired', 'invalid_credentials'};

/// 서버(backend `app/core/errors.py` `CODE_*`)가 POST /school-email/verify 오류의 `code` 에 싣는 값.
const _codeAlreadyVerified = 'SCHOOL_EMAIL_ALREADY_VERIFIED';
const _codeNotConfirmed = 'SCHOOL_EMAIL_NOT_CONFIRMED';
// ALIAS_NOT_ALLOWED: 학교 메일 `+` 별칭(422). 같은 메일로는 다시 해도 같은 답이라 임시 연결을 비운다.
const _codesRejected = {'SCHOOL_EMAIL_DOMAIN_NOT_ALLOWED', 'SCHOOL_EMAIL_REJOIN_BLOCKED', 'SCHOOL_EMAIL_ALIAS_NOT_ALLOWED'};
const _codeAuthUnavailable = 'AUTH_UNAVAILABLE';

/// ponytail: code 가 없는 옛 서버 호환용 문구 비교 — 서버 배포 뒤 제거 가능. 글자까지 같아야 한다.
// l10n-ignore-start(server-text): 서버 errors.py 문구와 글자까지 같아야 하는 비교 상수(code 없는 옛 서버 호환) — ARB 로 옮기면 분기가 조용히 죽는다
const _alreadyVerified = '이미 학교 메일 인증이 끝났어요'; // SCHOOL_EMAIL_ALREADY_VERIFIED
const _notConfirmed = '학교 메일 인증이 끝나지 않았어요'; // SCHOOL_EMAIL_NOT_CONFIRMED

/// 422 거절 문구(옛 서버 호환). 재가입 제한은 훅("…이메일이에요")과 서버("…메일이에요") 글자가 달라 둘 다 둔다.
const _rejectedMessages = {
  unknownSchoolEmailMessage, // 인터페이스(school_email_repository.dart)에 둔다 — 02 화면 상태도 쓴다
  '허용되지 않은 학교 이메일이에요', // 옛 훅 문구, 호환용
  '재가입이 제한된 메일이에요', // 서버 SCHOOL_EMAIL_BLOCKED
  '재가입이 제한된 이메일이에요', // 훅 HOOK_BLOCKED
};
// l10n-ignore-end

/// [SchoolEmailRepository]를 임시 Supabase 연결 + FastAPI 로 구현한다.
class SupabaseSchoolEmailRepository implements SchoolEmailRepository {
  SupabaseSchoolEmailRepository(this._api, this._connection, this._auth);

  /// 메인(소셜) 연결의 토큰을 붙이는 서버 클라이언트.
  final ApiClient _api;

  /// 학교 메일 OTP 전용 임시 연결. 메인 연결이 아니다.
  final TemporaryAuthConnection _connection;

  /// 메인(소셜) 연결. 로그인한 계정의 가입 방식을 읽기만 한다.
  final GoTrueClient _auth;

  /// 로그인한 소셜 계정과 같은 메일(학교 구글 계정으로 로그인)이어도 보낸다 — GoTrue 가 그 계정으로 OTP 로그인시키고
  /// 서버가 OTP 를 메일 주인 증거로 받아 인증한다(서버 6-f, 2026-11-23).
  ///
  /// GoTrue 호출은 앱 쓰기 상한([writeTimeout])에서 끊는다 — 망이 끊겨 답이 안 오면 버튼이 "진행 중" 에 묶였다.
  /// 시간 초과(TimeoutException)도 Exception 이라 다른 네트워크 실패와 같은 Failure 가 된다.
  ///
  /// 새 코드가 나간 뒤에는 임시 연결에 남은 세션(앞 코드가 늦게 성공한 것)을 비운다 — 남겨 두면 [verifyCode] 가
  /// 새 코드를 보지 않고 그 세션을 쓴다. 보내기가 실패하면 그 세션이 유일한 길이라 남긴다.
  @override
  Future<Result<void>> requestCode(UniversityEmail email) async {
    try {
      await _connection.open().signInWithOtp(email: email.toRequestValue(), shouldCreateUser: true).timeout(writeTimeout);
    } on AuthException catch (error) {
      return FailureResult(_toRequestFailure(error));
    } on Exception {
      return const FailureResult(CodeNotSentFailure());
    }
    // 연결째 닫아도 된다 — 임시 연결은 implicit 흐름이라 verifyOTP 는 보낸 연결의 상태(PKCE)를 쓰지 않는다.
    if (_connection.open().currentSession != null) {
      await _close();
    }
    return const Success(null);
  }

  /// 시간 초과 뒤 앞선 확인이 늦게 성공했으면 임시 연결에 이 메일의 세션이 이미 있다 — 코드는 이미 쓰였으니
  /// 다시 확인하지 않고 그 토큰을 쓴다(다시 확인하면 "코드가 맞지 않아요" 가 된다).
  @override
  Future<Result<String>> verifyCode(UniversityEmail email, VerificationCode code) async {
    final earlier = _connection.open().currentSession;
    if (earlier != null && UniversityEmail.tryParse(earlier.user.email ?? '') == email) {
      return Success(earlier.accessToken);
    }
    try {
      final response = await _connection
          .open()
          .verifyOTP(email: email.toRequestValue(), token: code.toRequestValue(), type: OtpType.email)
          .timeout(writeTimeout);
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
      await _close();
    }
    return failure == null ? const Success(null) : FailureResult(failure);
  }

  @override
  Future<void> discard() => _close();

  /// 임시 연결 로그아웃은 메모리 세션을 먼저 비우고 서버에 알린다 — 그 알림이 안 끝나도 상한에서 기다리기를 멈춘다.
  Future<void> _close() => _connection.close().timeout(writeTimeout, onTimeout: () {});

  /// 지금 로그인한 소셜(`account_repository.dart` 와 같은 방식). 모르면 null — 다른 소셜로 보고 다시 로그인 길을 연다.
  String? _myProvider() {
    final provider = _auth.currentUser?.appMetadata['provider'];
    return provider is String ? provider : null;
  }

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
  /// 409(이미 쥔 계정, http_send 가 이미 가름)는 내 소셜을 덧붙여 올린다 — 같은 소셜이면 안내가 달라진다(설계 5-3).
  /// 세션 · 정지 같은 나머지는 그대로 올린다.
  Failure? _toCompleteFailure(Failure failure) {
    if (failure is SchoolEmailTakenFailure) {
      return failure.withMyProvider(_myProvider());
    }
    if (failure is ServerRejectedFailure) {
      return failure.hasAnyCode() ? _byCode(failure) : _byMessage(failure);
    }
    // 알 수 없는 오류(UnknownFailure)는 일시 오류로 보고 임시 연결을 남긴다 — 같은 03 에서 complete 만 다시 부를 수 있게.
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
      return SchoolEmailRejectedFailure(failure.serverMessage);
    }
    return failure.hasCode(_codeAuthUnavailable) ? const SchoolEmailIncompleteFailure() : failure;
  }

  /// ponytail: code 없는 옛 서버 호환 — 서버 배포 뒤 제거 가능.
  Failure? _byMessage(ServerRejectedFailure failure) {
    final message = failure.serverMessage;
    if (message == _alreadyVerified) {
      return null;
    }
    if (message == _notConfirmed) {
      return const SchoolEmailNotConfirmedFailure();
    }
    return _rejectedMessages.contains(message) ? SchoolEmailRejectedFailure(message) : failure;
  }
}
