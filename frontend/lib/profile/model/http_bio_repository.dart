import 'dart:convert';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/http_send.dart';
import 'package:campus_mate/profile/model/bio_repository.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// [BioRepository]를 FastAPI 호출로 구현한다.
class HttpBioRepository implements BioRepository {
  const HttpBioRepository(this._baseUrl, this._client, this._auth);

  final String _baseUrl;
  final http.Client _client;
  final GoTrueClient _auth;

  @override
  Future<Result<String>> generateDraft() async {
    final result = await sendAuthorizedRequest(
      _client,
      _auth,
      (accessToken) => http.Request('POST', Uri.parse('$_baseUrl/profile-onboarding/bio-draft'))
      ..headers['Authorization'] = 'Bearer $accessToken',
    );
    return result.when(
      onSuccess: (response) => Success((jsonDecode(response.body) as Map<String, dynamic>)['draft'] as String),
      onFailure: (failure) => FailureResult(failure),
    );
  }

  @override
  Future<Result<void>> submit(String bio) async {
    final result = await sendAuthorizedRequest(
      _client,
      _auth,
      (accessToken) => http.Request('POST', Uri.parse('$_baseUrl/profile-onboarding/bio'))
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'bio': bio}),
    );
    return result.when(
      onSuccess: (_) => const Success(null),
      onFailure: (failure) => FailureResult(failure),
    );
  }
}
