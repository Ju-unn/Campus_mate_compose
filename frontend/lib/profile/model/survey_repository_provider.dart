import 'package:campus_mate/core/env.dart';
import 'package:campus_mate/profile/model/http_survey_repository.dart';
import 'package:campus_mate/profile/model/survey_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

final surveyRepositoryProvider = Provider<SurveyRepository>((ref) {
  return HttpSurveyRepository(Env.apiBaseUrl, http.Client(), Supabase.instance.client.auth);
});
