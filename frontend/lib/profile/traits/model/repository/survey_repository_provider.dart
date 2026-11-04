import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:campus_mate/profile/traits/model/repository/http_survey_repository.dart';
import 'package:campus_mate/profile/traits/model/repository/survey_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final surveyRepositoryProvider = Provider<SurveyRepository>((ref) {
  return HttpSurveyRepository(ref.read(apiClientProvider));
});
