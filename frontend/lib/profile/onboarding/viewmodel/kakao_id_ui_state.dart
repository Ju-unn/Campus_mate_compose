import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/input_rules.dart';

/// 카카오톡 아이디 화면(DESIGN.md 화면 04-1b)의 상태.
class KakaoIdUiState {
  const KakaoIdUiState({
    this.kakaoIdInput = '',
    this.kakaoIdChecked = false,
    this.isSubmitting = false,
    this.error,
    this.completed = false,
  });

  final String kakaoIdInput;

  /// 쓰다 손을 멈췄다(300ms 디바운스) — 공백 아닌 거절 이유는 이때부터 칸 아래에 알린다.
  final bool kakaoIdChecked;
  final bool isSubmitting;
  final Failure? error;
  final bool completed;

  /// 칸 아래 빨간 한 줄 — 서버 실패가 먼저, 아니면 미리 검사(pen gprMl I-4, 규칙은 `kakaoIdFieldError`).
  Failure? get fieldError => error ?? kakaoIdFieldError(kakaoIdInput, settled: kakaoIdChecked);

  /// 서버 `is_valid_kakao_id` 와 같은 규칙에 맞을 때만(빈 값 · 공백만도 여기서 걸린다). 기준은 서버다.
  bool get canSubmit => isValidKakaoId(kakaoIdInput) && !isSubmitting;
}
