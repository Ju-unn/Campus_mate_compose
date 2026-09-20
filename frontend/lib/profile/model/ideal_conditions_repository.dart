import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';

/// 06-1 이상형 조건 제출값.
class IdealConditionsSubmission {
  const IdealConditionsSubmission({
    required this.preferredAgeMin,
    required this.preferredAgeMax,
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
}

abstract interface class IdealConditionsRepository {
  Future<Result<void>> submit(IdealConditionsSubmission submission);
}
