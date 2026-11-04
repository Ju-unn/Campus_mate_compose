import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/profile/ideal/model/data/ideal_conditions_submission.dart';
import 'package:campus_mate/profile/ideal/model/repository/ideal_conditions_repository.dart';

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
          // null 을 보내면 서버가 저장값을 null 로 되돌린다 — 안 골랐으면 키를 아예 싣지 않는다.
          'accepts_smoker': ?submission.acceptsSmoker,
        },
      );
}
