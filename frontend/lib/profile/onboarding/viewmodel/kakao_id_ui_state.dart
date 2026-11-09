import 'package:campus_mate/common/failure.dart';

/// 카카오톡 아이디 화면(DESIGN.md 화면 04-1b)의 상태.
class KakaoIdUiState {
  const KakaoIdUiState({
    this.kakaoIdInput = '',
    this.isSubmitting = false,
    this.error,
    this.completed = false,
  });

  final String kakaoIdInput;
  final bool isSubmitting;
  final Failure? error;
  final bool completed;

  bool get canSubmit => kakaoIdInput.trim().isNotEmpty && !isSubmitting;
}
