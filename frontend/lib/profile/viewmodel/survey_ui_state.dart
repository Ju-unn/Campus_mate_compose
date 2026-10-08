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

  /// 슬라이더 양 끝 값. 이 밖의 값은 저장한 적이 없는 값이다.
  static const double _answerLimit = 1;

  /// 폰에 임시 저장할 값 — 9개 축 · 종교 · 흡연. JSON 키는 글자라 축 번호도 글자로 적는다.
  Map<String, Object?> toDraft() => {
        'answers': {for (final entry in answers.entries) '${entry.key}': entry.value},
        'religion': religion?.name,
        'isSmoker': isSmoker,
      };

  /// [toDraft] 로 남긴 값으로 처음 상태를 만든다. 남기지 않은 축은 가운데(0)로 채운다.
  /// 축 번호나 값이 범위를 벗어나거나 종교 이름을 모르면 던진다 — 저장소가 받아서 버린다.
  static SurveyUiState fromDraft(Map<String, Object?> data) {
    final saved = {
      for (final entry in (data['answers'] as Map<String, Object?>).entries)
        int.parse(entry.key): (entry.value as num).toDouble(),
    };
    if (saved.entries.any((e) => e.key < 1 || e.key > axisCount || e.value.abs() > _answerLimit)) {
      throw const FormatException('성향 축 번호 · 값이 범위를 벗어남');
    }
    final religion = data['religion'] as String?;
    return SurveyUiState(
      answers: {for (var axis = 1; axis <= axisCount; axis++) axis: saved[axis] ?? 0},
      religion: religion == null ? null : Religion.values.byName(religion),
      isSmoker: data['isSmoker'] as bool?,
    );
  }
}
