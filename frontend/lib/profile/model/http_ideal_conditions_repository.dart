import 'dart:convert';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/http_send.dart';
import 'package:campus_mate/profile/model/ideal_conditions_repository.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// [IdealConditionsRepository]를 FastAPI 호출로 구현한다.
class HttpIdealConditionsRepository implements IdealConditionsRepository {
  const HttpIdealConditionsRepository(this._baseUrl, this._client, this._auth);

  final String _baseUrl;
  final http.Client _client;
  final GoTrueClient _auth;

  @override
  Future<Result<void>> submit(IdealConditionsSubmission submission) async {
    final result = await sendAuthorizedRequest(
      _client,
      _auth,
      (accessToken) => http.Request('POST', Uri.parse('$_baseUrl/profile-onboarding/ideal-conditions'))
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
      'preferred_age_min': submission.preferredAgeMin,
      'preferred_age_max': submission.preferredAgeMax,
      'preferred_height_min': submission.preferredHeightMin,
      'preferred_height_max': submission.preferredHeightMax,
      'preferred_mbti_flags': submission.preferredMbtiFlags,
      'preferred_animal_types': submission.preferredAnimalTypes.map((e) => e.name).toList(),
      'preferred_impression_types': submission.preferredImpressionTypes.map((e) => e.name).toList(),
      }),
    );
    return result.when(
      onSuccess: (_) => const Success(null),
      onFailure: (failure) => FailureResult(failure),
    );
  }
}
