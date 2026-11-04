import 'package:campus_mate/common/failure.dart';

/// 구글 플레이 심사원 아이디 · 비밀번호 창의 상태. 이메일 · 비밀번호는 여기 담지 않는다 —
/// 입력칸이 들고 있다가 누를 때 한 번 넘기고, 시트가 닫히면 함께 사라진다(상태 · 로그 · 분석에 남기지 않는다).
class ReviewerLoginUiState {
  const ReviewerLoginUiState({this.isSubmitting = false, this.failure, this.completed = false});

  final bool isSubmitting;

  /// 실패한 종류. 글자는 view 가 `context.errorText(failure)` 로 만든다. 없으면 null.
  final Failure? failure;

  /// 로그인이 끝났다 — 시트가 이 신호로 닫힌다. 이후 흐름은 세션 리스너 → 게이트 → 라우터가 맡는다.
  final bool completed;

  /// 두 칸이 모두 찼는지. 이메일은 앞뒤 공백을 뺀 글자가, 비밀번호는 공백도 글자로 센다.
  static bool isFilled(String email, String password) => email.trim().isNotEmpty && password.isNotEmpty;
}
