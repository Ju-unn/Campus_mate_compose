import 'package:campus_mate/profile/model/profile_enums.dart';

/// 성향 설문 화면(DESIGN.md 화면 05-01~11)의 상태. 9축 + 종교 + 흡연.
class SurveyUiState {
  const SurveyUiState({
    this.answers = const {},
    this.religion,
    this.isSmoker,
    this.isSubmitting = false,
    this.errorMessage,
    this.completed = false,
  });

  final Map<int, double> answers;
  final Religion? religion;
  final bool? isSmoker;
  final bool isSubmitting;
  final String? errorMessage;
  final bool completed;

  bool get canSubmit => answers.length == 9 && religion != null && isSmoker != null && !isSubmitting;
}
