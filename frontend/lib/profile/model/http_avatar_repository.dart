import 'dart:convert';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/http_send.dart';
import 'package:campus_mate/profile/model/avatar_generation_outcome.dart';
import 'package:campus_mate/profile/model/avatar_repository.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// [AvatarRepository]를 FastAPI 호출로 구현한다.
class HttpAvatarRepository implements AvatarRepository {
  const HttpAvatarRepository(this._baseUrl, this._client, this._auth);

  final String _baseUrl;
  final http.Client _client;
  final GoTrueClient _auth;

  @override
  Future<Result<AvatarGenerationOutcome>> generateAvatar() async {
    final result = await sendAuthorizedRequest(
      _client,
      _auth,
      (accessToken) => http.Request('POST', Uri.parse('$_baseUrl/profile-onboarding/avatar/generate'))
      ..headers['Authorization'] = 'Bearer $accessToken',
    );
    return result.when(
      onSuccess: (response) => Success(_toOutcome(response)),
      onFailure: (failure) => FailureResult(failure),
    );
  }

  AvatarGenerationOutcome _toOutcome(http.Response response) {
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return switch (body['status'] as String) {
      'ready' => AvatarReady(body['storage_path'] as String),
      'fallback' => AvatarFallback(body['compensation_hearts'] as int),
      _ => const AvatarFailed(),
    };
  }
}
