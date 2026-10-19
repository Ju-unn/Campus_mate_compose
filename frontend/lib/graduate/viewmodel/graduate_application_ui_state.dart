import 'dart:io';

import 'package:campus_mate/graduate/model/graduate_request_state.dart';
import 'package:campus_mate/graduate/model/previous_school_email.dart';

/// 졸업생 신청 폼의 상태. 동작 하나가 끝날 때마다 새로 만든다 — [errorMessage] 는 그 한 번에만 붙는다.
class GraduateApplicationUiState {
  const GraduateApplicationUiState({
    this.photo,
    this.previousEmailInput = '',
    this.agreed = false,
    this.isSubmitting = false,
    this.errorMessage,
    this.rejection,
    this.isExhausted = false,
  });

  final File? photo;

  /// 이전 학교 메일 입력칸의 글자(선택). 비어 있어도 보낼 수 있다.
  final String previousEmailInput;

  /// 개인정보 수집 동의 줄(계획서 D11 (나)). 누른 뒤에만 보낼 수 있다.
  final bool agreed;
  final bool isSubmitting;

  /// 화면이 토스트로 한 번 띄운다.
  final String? errorMessage;

  /// 반려된 뒤 다시 신청하는 폼이면 서버가 알려 준 사유 · 남은 횟수. 처음 신청이면 null.
  final GraduateRejected? rejection;

  /// 신청 횟수를 다 썼다 — 폼 대신 문의 안내를 보인다(반려 뒤 남은 횟수 0 이거나 신청이 429 로 막혔다).
  final bool isExhausted;

  /// 적었는데 형식이 틀렸다. 비어 있는 것은 틀린 것이 아니다.
  bool get isPreviousEmailInvalid =>
      previousEmailInput.trim().isNotEmpty && PreviousSchoolEmail.tryParse(previousEmailInput) == null;

  bool get canSubmit => photo != null && agreed && !isSubmitting && !isExhausted && !isPreviousEmailInvalid;

  GraduateApplicationUiState copyWith({
    File? photo,
    String? previousEmailInput,
    bool? agreed,
    bool? isSubmitting,
    String? errorMessage,
    GraduateRejected? rejection,
    bool? isExhausted,
  }) {
    return GraduateApplicationUiState(
      photo: photo ?? this.photo,
      previousEmailInput: previousEmailInput ?? this.previousEmailInput,
      agreed: agreed ?? this.agreed,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: errorMessage,
      rejection: rejection ?? this.rejection,
      isExhausted: isExhausted ?? this.isExhausted,
    );
  }
}
