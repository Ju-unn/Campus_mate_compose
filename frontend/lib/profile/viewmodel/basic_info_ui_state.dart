/// 기본 정보 화면(DESIGN.md 화면 04-1)의 상태.
class BasicInfoUiState {
  const BasicInfoUiState({
    this.nicknameInput = '',
    this.nicknameError,
    this.birthYearInput = '',
    this.heightInput = '',
    this.phoneNumberInput = '',
    this.gender,
    this.mbti,
    this.isSubmitting = false,
    this.errorMessage,
    this.completed = false,
  });

  final String nicknameInput;

  /// 형식은 맞지만 서버가 이미 있다고 답한 경우에만 채운다(디바운스 조회 결과).
  final String? nicknameError;
  final String birthYearInput;
  final String heightInput;
  final String phoneNumberInput;
  final String? gender;
  final String? mbti;
  final bool isSubmitting;
  final String? errorMessage;
  final bool completed;

  int? get birthYear {
    final value = int.tryParse(birthYearInput);
    return (value != null && value >= 1950 && value <= 2020) ? value : null;
  }

  int? get heightCm {
    final value = int.tryParse(heightInput);
    return (value != null && value >= 120 && value <= 230) ? value : null;
  }

  bool get _isNicknameValid {
    return RegExp(r'^[가-힣a-zA-Z]{2,5}$').hasMatch(nicknameInput) && nicknameError == null;
  }

  bool get canSubmit {
    return !isSubmitting &&
        _isNicknameValid &&
        birthYear != null &&
        heightCm != null &&
        phoneNumberInput.isNotEmpty &&
        gender != null;
  }
}
