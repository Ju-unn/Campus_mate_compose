import 'dart:convert';

import 'package:campus_mate/auth/model/http_send.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/tag_picker_repository.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// [TagPickerRepository]를 FastAPI 호출로 구현한다.
class HttpTagPickerRepository implements TagPickerRepository {
  const HttpTagPickerRepository(this._baseUrl, this._client, this._auth);

  final String _baseUrl;
  final http.Client _client;
  final GoTrueClient _auth;

  @override
  Future<Result<void>> submit(String endpoint, List<String> tags) async {
    final request = http.Request('POST', Uri.parse('$_baseUrl/profile-onboarding/$endpoint'))
      ..headers['Authorization'] = 'Bearer ${_auth.currentSession!.accessToken}'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'tags': tags});
    final result = await sendHttpRequest(_client, request);
    return result.when(
      onSuccess: (_) => const Success(null),
      onFailure: (failure) => FailureResult(failure),
    );
  }
}
