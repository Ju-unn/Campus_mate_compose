import 'package:campus_mate/consent/model/consent_item.dart';

/// 약관 동의(02-c)의 상태.
class ConsentUiState {
  const ConsentUiState({this.checked = const {}, this.isSubmitting = false, this.errorMessage});

  final Set<ConsentItem> checked;
  final bool isSubmitting;

  /// 저장이 실패했을 때 한 번 띄울 안내. 다시 보낼 때 지운다.
  final String? errorMessage;

  /// 전체 동의 줄의 체크 — 선택 항목(마케팅)까지 다 켜져야 켜진다.
  bool get allChecked => checked.length == ConsentItem.values.length;

  /// 필수 4개가 다 켜져야 "동의하고 계속하기"가 켜진다. 마케팅은 꺼도 된다.
  bool get canSubmit => !isSubmitting && ConsentItem.values.where((item) => item.isRequired).every(checked.contains);

  ConsentUiState copyWith({Set<ConsentItem>? checked, bool? isSubmitting, String? errorMessage}) {
    return ConsentUiState(
      checked: checked ?? this.checked,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: errorMessage,
    );
  }
}
