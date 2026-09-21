import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:campus_mate/profile/model/survey_repository.dart';

/// [SurveyRepository]를 FastAPI 호출로 구현한다.
class HttpSurveyRepository implements SurveyRepository {
  const HttpSurveyRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<void>> submit(Map<int, double> answers, Religion religion, bool isSmoker) =>
      _api.send(
        'POST',
        '/profile-onboarding/survey',
        (_) {},
        body: {
          'answers': answers.map((axis, value) => MapEntry(axis.toString(), value)),
          'religion': religion.name,
          'is_smoker': isSmoker,
        },
      );
}
