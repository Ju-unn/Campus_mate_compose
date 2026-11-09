import 'package:campus_mate/auth/social/model/data/social_provider.dart';
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
/// 안내([isInfo], 03 학교 메일 충돌 뒤 "카카오로 로그인해 주세요")는 버튼 폭에 `info` 다.
///
/// 글자는 여기서 정하지 않는다 — 글자의 출처가 셋이다: 실패의 종류([failure] — 로그인 실패 · 탈퇴 · 로그인 만료 알림, 화면이
/// `context.errorText` 로 바꾼다), 뒤로가기 한 번 더 안내([isBackExitHint], 화면이 문구 파일에서 읽는다), 03 다시 로그인 안내처럼
/// 화면이 이미 글자로 만들어 둔 [message].
class StartToast {
  const StartToast({
    this.message,
    this.failure,
    this.isBackExitHint = false,
    required this.isCancellation,
    this.isInfo = false,
  });

  factory StartToast.fromFailure(Failure failure) {
    return StartToast(failure: failure, isCancellation: failure is LoginCancelledFailure);
  }

  /// 이미 글자로 만들어진 알림(`LoginNotice`). 실패 · 뒤로가기 안내면 null.
  final String? message;

  /// 로그인이 실패한 종류 · 실패 종류로 남긴 로그아웃 알림(탈퇴 · 로그인 만료). 글자 알림 · 뒤로가기 안내면 null.
  final Failure? failure;

  /// "한 번 더 누르면 종료돼요" 안내.
  final bool isBackExitHint;
  final bool isCancellation;

  /// 오류가 아닌 안내 — 버튼 폭은 그대로, 아이콘만 `info`.
  final bool isInfo;
}
