import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/profile/model/ideal_conditions_repository.dart';

/// [IdealConditionsRepository]를 FastAPI 호출로 구현한다.
class HttpIdealConditionsRepository implements IdealConditionsRepository {
  const HttpIdealConditionsRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<void>> submit(IdealConditionsSubmission submission) => _api.send(
        'POST',
        '/profile-onboarding/ideal-conditions',
        (_) {},
        body: {
          'preferred_age_min': submission.preferredAgeMin,
          'preferred_age_max': submission.preferredAgeMax,
          'preferred_height_min': submission.preferredHeightMin,
          'preferred_height_max': submission.preferredHeightMax,
          'preferred_mbti_flags': submission.preferredMbtiFlags,
          'preferred_animal_types': submission.preferredAnimalTypes.map((e) => e.name).toList(),
          'preferred_impression_types':
              submission.preferredImpressionTypes.map((e) => e.name).toList(),
        },
      );
}
