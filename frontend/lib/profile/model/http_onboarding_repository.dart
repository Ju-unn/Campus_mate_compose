import 'dart:convert';

import 'package:campus_mate/auth/model/http_send.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/onboarding_repository.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// [OnboardingRepository]를 FastAPI 호출로 구현한다.
class HttpOnboardingRepository implements OnboardingRepository {
  const HttpOnboardingRepository(this._baseUrl, this._client, this._auth);

  final String _baseUrl;
  final http.Client _client;
  final GoTrueClient _auth;

  @override
  Future<Result<OnboardingStep>> fetchNextStep() async {
    final request = http.Request('GET', Uri.parse('$_baseUrl/profile-onboarding/next-step'))
      ..headers['Authorization'] = 'Bearer ${_auth.currentSession!.accessToken}';
    final result = await sendHttpRequest(_client, request);
    return result.when(
      onSuccess: (response) => Success(_toStep(response)),
      onFailure: (failure) => FailureResult(failure),
    );
  }

  OnboardingStep _toStep(http.Response response) {
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return OnboardingStep.fromWire(body['step'] as String);
  }
}
