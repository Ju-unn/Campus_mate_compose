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

  /// 성향 축 개수(1~9). 기본값을 채우는 쪽과 제출 조건이 같은 수를 봐야 한다.
  static const int axisCount = 9;

  final Map<int, double> answers;
  final Religion? religion;
  final bool? isSmoker;
  final bool isSubmitting;
  final String? errorMessage;
  final bool completed;

  bool get canSubmit =>
      answers.length == axisCount && religion != null && isSmoker != null && !isSubmitting;
}
