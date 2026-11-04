import 'package:campus_mate/auth/social/model/repository/social_login_repository_provider.dart';
import 'package:campus_mate/auth/social/viewmodel/reviewer_login_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 시트가 닫히면 상태(실패 표시 포함)를 버린다. 열 때마다 깨끗하게 시작한다.
final reviewerLoginViewModelProvider =
    NotifierProvider.autoDispose<ReviewerLoginViewModel, ReviewerLoginUiState>(ReviewerLoginViewModel.new);

/// 구글 플레이 심사원 아이디 · 비밀번호 로그인 흐름. 사용 통계 `login` 은 남기지 않는다(심사원 로그인이 통계에 섞이지 않게).
/// 성공 뒤 이동은 하지 않는다 — 세션이 생기면 `AuthSessionListenable` → 게이트 → 라우터가 다음 화면으로 보낸다.
class ReviewerLoginViewModel extends Notifier<ReviewerLoginUiState> {
  @override
  ReviewerLoginUiState build() => const ReviewerLoginUiState();

  /// 이메일 · 비밀번호는 이 호출 안에서만 쓰고 어디에도 담지 않는다.
  Future<void> signIn(String email, String password) async {
    // 빈 칸이거나 진행 중이면 무시한다(중복 탭).
    if (state.isSubmitting || !ReviewerLoginUiState.isFilled(email, password)) {
      return;
    }
    state = const ReviewerLoginUiState(isSubmitting: true);
    final result = await ref.read(socialLoginRepositoryProvider).signInWithPassword(email.trim(), password);
    // 요청 도중 시트가 닫혔거나 세션 변화로 화면이 걷혔으면 상태를 만지지 않는다.
    if (!ref.mounted) {
      return;
    }
    state = result.when(
      onSuccess: (_) => const ReviewerLoginUiState(completed: true),
      onFailure: (failure) => ReviewerLoginUiState(failure: failure),
    );
  }
}
