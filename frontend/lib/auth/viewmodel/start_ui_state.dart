import 'package:campus_mate/auth/model/social_provider.dart';
import 'package:campus_mate/common/failure.dart';

/// 시작 화면(스플래시를 고친 것)의 소셜 로그인 상태.
///
/// 버튼 영역을 그릴지(로그아웃이 확인됐는지)는 여기 두지 않는다 — 세션 리스너를 화면이 직접 본다.
class StartUiState {
  const StartUiState({this.inProgress, this.toast});

  /// 지금 로그인 중인 공급자. 그 버튼만 레이블 대신 스피너, 나머지는 비활성.
  final SocialProvider? inProgress;

  /// 버튼 영역 바로 위에 잠깐 뜨는 알약. 없으면 null.
  final StartToast? toast;

  bool isLoading(SocialProvider provider) => inProgress == provider;

  /// 하나라도 진행 중이면 모든 버튼을 막는다(중복 탭 무시).
  bool isEnabled(SocialProvider provider) => inProgress == null;
}

/// 시작 화면 토스트 한 장. 취소는 아이콘 없이, 실패 · 로그아웃 알림은 경고 아이콘과 함께(대장 지시문 07).
class StartToast {
  const StartToast({required this.message, required this.hasWarningIcon});

  factory StartToast.fromFailure(Failure failure) {
    return StartToast(message: failure.toDisplayMessage(), hasWarningIcon: failure is! LoginCancelledFailure);
  }

  final String message;
  final bool hasWarningIcon;
}
