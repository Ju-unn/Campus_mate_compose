/// 추천 코드는 대문자 · 숫자 6자다(2026-09-28 대장 D3, DB check `^[A-HJ-NP-Z2-9]{6}$`).
const referralCodeLength = 6;

/// 추천 코드 입력 화면(DESIGN.md 화면 20)의 상태. 선택 화면이라 건너뛸 수 있다.
class ReferralCodeUiState {
  const ReferralCodeUiState({
    this.code = '',
    this.isSubmitting = false,
    this.errorMessage,
    this.referrerId,
  });

  final String code;
  final bool isSubmitting;
  final String? errorMessage;

  /// 코드가 확인되면 채워진다 — 화면은 이것을 보고 다음(20d, 나중에 20b)으로 옮긴다.
  final String? referrerId;

  /// 보내는 중이면 거짓이라 두 번째 누름을 막는다.
  bool get canSubmit => code.length == referralCodeLength && !isSubmitting;

  /// [errorMessage] 는 넘기지 않으면 지운다 — 코드를 고치면 오류가 사라진다.
  ReferralCodeUiState copyWith({
    String? code,
    bool? isSubmitting,
    String? errorMessage,
    String? referrerId,
  }) {
    return ReferralCodeUiState(
      code: code ?? this.code,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: errorMessage,
      referrerId: referrerId ?? this.referrerId,
    );
  }
}
