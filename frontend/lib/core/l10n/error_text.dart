import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';

/// 에러 문구(문구 파일 `lib/l10n/app_ko.arb` 의 `error*` 키)를 읽는 **유일한 파일**이다.
/// 뷰모델은 [Failure] 종류만 내고, view 가 `context.errorText(failure)` 로 글자로 바꾼다 — 에러 문구를 따로 고르는
/// 코드가 생기면 `test/l10n/error_key_scope_test.dart` 가 잡는다.
///
/// `switch` 가 sealed [Failure] 를 빠짐없이 덮는다 — 하위 형을 더하고 여기를 빼먹으면 컴파일이 먼저 실패한다.
/// 서버가 준 문구를 그대로 보이는 가지(거절 4종)만 ARB 를 쓰지 않는다(서버 `detail` 이 기준이다).
String failureText(AppLocalizations l10n, Failure failure) => switch (failure) {
      NetworkFailure() => l10n.errorNetwork,
      SessionExpiredFailure() => l10n.errorSessionExpired,
      NotFoundFailure() => l10n.errorNotFound,
      UnknownFailure() => l10n.errorUnknown,
      ServerUnavailableFailure() => l10n.errorServerUnavailable,
      RateLimitedFailure(:final serverMessage) => serverMessage ?? l10n.errorRateLimited,
      SignUpRejectedFailure(:final serverMessage) => serverMessage,
      WrongCodeFailure() => l10n.errorWrongCode,
      ServerRejectedFailure(:final serverMessage) => serverMessage,
      SuspendedFailure() => l10n.errorSuspended,
      WithdrawnFailure() => l10n.errorWithdrawn,
      CodeNotSentFailure() => l10n.errorCodeNotSent,
      SchoolEmailIncompleteFailure() || SchoolEmailNotConfirmedFailure() => l10n.errorSchoolEmailIncomplete,
      SchoolEmailSameAsLoginFailure() => l10n.errorSchoolEmailSameAsLogin,
      SchoolEmailRejectedFailure(:final serverMessage) => serverMessage,
      final SchoolEmailTakenFailure taken => _takenText(l10n, taken),
      LoginCancelledFailure() => l10n.errorLoginCancelled,
      SocialLoginFailure() => l10n.errorSocialLogin,
      AppErrorFailure(:final error) => appErrorKindText(l10n, error),
    };

/// 앱이 정하는 에러 종류([AppError])의 글자. 화면이 [Failure] 객체 없이 직접 알리는 자리(실패 패널 등)가 쓴다.
String appErrorKindText(AppLocalizations l10n, AppError error) => switch (error) {
      AppError.notificationsLoad => l10n.errorNotificationsLoad,
      AppError.storeOpenFailed => l10n.errorStoreOpenFailed,
      AppError.tryLater => l10n.errorTryLater,
    };

String _takenText(AppLocalizations l10n, SchoolEmailTakenFailure failure) {
  if (failure.isTakenByEmailAccount()) return l10n.errorSchoolEmailTakenByEmailAccount;
  if (!failure.isTakenBySocial()) return failure.serverMessage;
  final other = failure.otherSocialProvider();
  return other == null ? l10n.errorSchoolEmailTaken : l10n.errorSchoolEmailTakenBy(provider: other);
}

/// 학교 메일 중복 오류 첫 줄 아래 둘째 줄. 소셜이 쥔 메일이 아니면 null.
String? takenHintText(AppLocalizations l10n, SchoolEmailTakenFailure failure) {
  if (!failure.isTakenBySocial()) return null;
  final other = failure.otherSocialProvider();
  return other == null ? l10n.errorSchoolEmailTakenHint : l10n.errorSchoolEmailTakenHintBy(provider: other);
}

/// 다시 로그인 단추를 누른 뒤 시작 화면에 남길 알림. 다른 소셜이 쥔 메일이 아니면 null.
String? takenReloginNoticeText(AppLocalizations l10n, SchoolEmailTakenFailure failure) {
  final other = failure.otherSocialProvider();
  return other == null ? null : l10n.errorSchoolEmailReloginNotice(provider: other);
}

/// 화면에서 에러를 글자로 읽는 길: `context.errorText(failure)` · `context.appErrorText(AppError.tryLater)`.
extension ErrorTextContext on BuildContext {
  String errorText(Failure failure) => failureText(l10n, failure);

  String appErrorText(AppError error) => appErrorKindText(l10n, error);
}
