import 'package:campus_mate/auth/model/social_login_repository_provider.dart';
import 'package:campus_mate/auth/model/social_provider.dart';
import 'package:campus_mate/auth/viewmodel/start_ui_state.dart';
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
  }

  /// 로그아웃하며 남긴 알림(탈퇴 · 로그인 만료 — `LoginNotice`)을 같은 토스트 자리에 띄운다.
  void showNotice(String message) {
    state = StartUiState(inProgress: state.inProgress, toast: StartToast(message: message, isCancellation: false));
  }

  /// 몇 초 뒤 화면이 부른다.
  void dismissToast() {
    state = StartUiState(inProgress: state.inProgress);
  }
}
