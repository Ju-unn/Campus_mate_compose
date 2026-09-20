import 'dart:convert';

import 'package:campus_mate/auth/model/http_send.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:campus_mate/profile/model/survey_repository.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// [SurveyRepository]를 FastAPI 호출로 구현한다.
class HttpSurveyRepository implements SurveyRepository {
  const HttpSurveyRepository(this._baseUrl, this._client, this._auth);

  final String _baseUrl;
  final http.Client _client;
  final GoTrueClient _auth;

  @override
  Future<Result<void>> submit(Map<int, double> answers, Religion religion, bool isSmoker) async {
    final result = await sendAuthorizedRequest(
      _client,
      _auth,
      (accessToken) => http.Request('POST', Uri.parse('$_baseUrl/profile-onboarding/survey'))
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
      'answers': answers.map((axis, value) => MapEntry(axis.toString(), value)),
      'religion': religion.name,
      'is_smoker': isSmoker,
      }),
    );
    return result.when(
      onSuccess: (_) => const Success(null),
      onFailure: (failure) => FailureResult(failure),
    );
  }
}
