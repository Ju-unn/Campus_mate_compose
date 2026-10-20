import 'package:campus_mate/auth/model/social_login_repository_provider.dart';
import 'package:campus_mate/auth/model/social_provider.dart';
import 'package:campus_mate/auth/viewmodel/start_ui_state.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/analytics/analytics_provider.dart';
import 'package:campus_mate/core/back_exit/back_exit_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final startViewModelProvider = NotifierProvider<StartViewModel, StartUiState>(StartViewModel.new);

/// 시작 화면의 소셜 로그인 흐름. 성공 뒤 이동은 하지 않는다 —
/// 세션이 생기면 `AuthSessionListenable` → 게이트 → 라우터가 다음 화면으로 보낸다.
class StartViewModel extends Notifier<StartUiState> {
  @override
  StartUiState build() => const StartUiState();

  Future<void> signIn(SocialProvider provider) async {
    // 진행 중이면 같은 버튼이든 다른 버튼이든 무시한다.
    if (state.inProgress != null) {
      return;
    }
    state = StartUiState(inProgress: provider);
    final result = await ref.read(socialLoginRepositoryProvider).signIn(provider);
    state = result.when(
      onSuccess: (_) => const StartUiState(),
      onFailure: (failure) => StartUiState(toast: StartToast.fromFailure(failure)),
    );
    // 사용 통계 `login` — 방법 이름(kakao · google · apple)만 남긴다. 약관 동의 전이라 수집이 켜질 때까지 서비스가 들고 있는다.
    if (result case Success()) {
      ref.read(analyticsServiceProvider).logLogin(provider.name);
    }
  }

  /// 로그아웃하며 남긴 알림(탈퇴 · 로그인 만료 · 03 학교 메일 충돌 — `LoginNotice`)을 같은 토스트 자리에 띄운다.
  void showNotice(String message, {bool isInfo = false}) {
    state = StartUiState(
      inProgress: state.inProgress,
      toast: StartToast(message: message, isCancellation: false, isInfo: isInfo),
    );
  }

  /// 안드로이드 뒤로가기로 앱이 닫히려 할 때 "한 번 더 누르면 종료돼요" 를 같은 토스트 자리에 띄운다(info 아이콘, 취소 토스트와 같은 모양).
  void showBackExitHint() {
    state = StartUiState(
      inProgress: state.inProgress,
      toast: const StartToast(message: backExitMessage, isCancellation: true),
    );
  }

  /// 몇 초 뒤 화면이 부른다.
  void dismissToast() {
    state = StartUiState(inProgress: state.inProgress);
  }
}
