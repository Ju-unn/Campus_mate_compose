import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:campus_mate/profile/model/http_survey_repository.dart';
import 'package:campus_mate/profile/model/survey_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final surveyRepositoryProvider = Provider<SurveyRepository>((ref) {
  return HttpSurveyRepository(ref.read(apiClientProvider));
});
