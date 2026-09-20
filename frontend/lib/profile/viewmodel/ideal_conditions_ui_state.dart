import 'package:campus_mate/profile/model/profile_enums.dart';

/// 이상형 조건 화면(DESIGN.md 화면 06-1)의 상태.
///
/// 나이·키는 `range-slider` 프리셋(§8.5)이라 기본값이 있고 비어 있을 수 없다. "상관없어요"는
/// 값을 지우는 대신 따로 표시해 두고, 제출할 때 키는 null, 나이는 전 구간으로 바꿔 보낸다
/// (서버 `preferred_age_min`·`preferred_age_max` 는 필수라 null 을 받지 못한다).
class IdealConditionsUiState {
  const IdealConditionsUiState({
    this.preferredAgeMin = 22,
    this.preferredAgeMax = 27,
    this.ageIgnored = false,
    this.preferredHeightMin = 165,
    this.preferredHeightMax = 180,
    this.heightIgnored = false,
    this.preferredMbtiFlags = const {},
    this.preferredAnimalTypes = const [],
    this.preferredImpressionTypes = const [],
    this.isSubmitting = false,
    this.errorMessage,
    this.completed = false,
  });

  /// 나이 프리셋 19세 ~ 35세 이상, 1세 단위(DESIGN.md §8.5).
  static const int ageFloor = 19;
  static const int ageCeiling = 35;

  /// 키 프리셋 150cm 이하 ~ 190cm 이상, 5cm 단위(DESIGN.md §8.5).
  static const int heightFloor = 150;
  static const int heightCeiling = 190;
  static const int heightStep = 5;

  /// 얼굴상·인상 선호는 각각 1~3개 필수다(DESIGN.md §8.5, 2026-09-20 사용자 결정으로 선택 → 필수).
  static const int maxAppearanceChoices = 3;

  /// 선호 MBTI 토글 8극(DESIGN.md §8.5 `mbti-toggle`).
  static const List<String> mbtiPoles = ['E', 'I', 'N', 'S', 'T', 'F', 'J', 'P'];

  final int preferredAgeMin;
  final int preferredAgeMax;
  final bool ageIgnored;
  final int preferredHeightMin;
  final int preferredHeightMax;
  final bool heightIgnored;
  final Map<String, bool> preferredMbtiFlags;
  final List<AnimalType> preferredAnimalTypes;
  final List<ImpressionType> preferredImpressionTypes;
  final bool isSubmitting;
  final String? errorMessage;
  final bool completed;

  bool get canSubmit {
    return !isSubmitting &&
        preferredAgeMin <= preferredAgeMax &&
        preferredHeightMin <= preferredHeightMax &&
        preferredAnimalTypes.isNotEmpty &&
        preferredAnimalTypes.length <= maxAppearanceChoices &&
        preferredImpressionTypes.isNotEmpty &&
        preferredImpressionTypes.length <= maxAppearanceChoices;
  }

  IdealConditionsUiState copyWith({
    int? preferredAgeMin,
    int? preferredAgeMax,
    bool? ageIgnored,
    int? preferredHeightMin,
    int? preferredHeightMax,
    bool? heightIgnored,
    Map<String, bool>? preferredMbtiFlags,
    List<AnimalType>? preferredAnimalTypes,
    List<ImpressionType>? preferredImpressionTypes,
    bool? isSubmitting,
    String? errorMessage,
    bool? completed,
  }) {
    return IdealConditionsUiState(
      preferredAgeMin: preferredAgeMin ?? this.preferredAgeMin,
      preferredAgeMax: preferredAgeMax ?? this.preferredAgeMax,
      ageIgnored: ageIgnored ?? this.ageIgnored,
      preferredHeightMin: preferredHeightMin ?? this.preferredHeightMin,
      preferredHeightMax: preferredHeightMax ?? this.preferredHeightMax,
      heightIgnored: heightIgnored ?? this.heightIgnored,
      preferredMbtiFlags: preferredMbtiFlags ?? this.preferredMbtiFlags,
      preferredAnimalTypes: preferredAnimalTypes ?? this.preferredAnimalTypes,
      preferredImpressionTypes: preferredImpressionTypes ?? this.preferredImpressionTypes,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: errorMessage,
      completed: completed ?? this.completed,
    );
  }
}
