import 'package:campus_mate/profile/onboarding/model/data/profile_enums.dart';

/// 06-1 이상형 조건 제출값.
class IdealConditionsSubmission {
  const IdealConditionsSubmission({
    required this.preferredAgeMin,
    required this.preferredAgeMax,
    required this.acceptsSmoker,
    this.preferredHeightMin,
    this.preferredHeightMax,
    this.preferredMbtiFlags = const {},
    this.preferredAnimalTypes = const [],
    this.preferredImpressionTypes = const [],
  });

  final int preferredAgeMin;
  final int preferredAgeMax;
  final int? preferredHeightMin;
  final int? preferredHeightMax;
  final Map<String, bool> preferredMbtiFlags;
  final List<AnimalType> preferredAnimalTypes;
  final List<ImpressionType> preferredImpressionTypes;

  /// 흡연하는 사람이 괜찮은가(앱 1.0.2) — true = 상관없어요, false = 싫어요. null = 아직 안 골랐다(흡연 여부도 모르던 사람).
  /// null 은 보내지 않는다 — 서버가 키가 없으면 DB 값을 안 건드리고, DB 가 null 이면 내 흡연 여부를 따른다.
  final bool? acceptsSmoker;
}
