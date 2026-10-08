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

/// 시작 화면 토스트 한 장(후속 지시문 13 B-3).
/// 취소는 폭을 내용에 맞추고 `info` 아이콘(높이 40), 실패 · 로그아웃 알림은 버튼 폭에 `triangle-alert`(두 줄이면 높이 60).
class StartToast {
  const StartToast({required this.message, required this.isCancellation});

  factory StartToast.fromFailure(Failure failure) {
    return StartToast(message: failure.toDisplayMessage(), isCancellation: failure is LoginCancelledFailure);
  }

  final String message;
  final bool isCancellation;
}
