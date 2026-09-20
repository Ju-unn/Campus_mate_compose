import 'dart:convert';

import 'package:campus_mate/auth/model/http_send.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/ideal_note_repository.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// [IdealNoteRepository]를 FastAPI 호출로 구현한다.
class HttpIdealNoteRepository implements IdealNoteRepository {
  const HttpIdealNoteRepository(this._baseUrl, this._client, this._auth);

  final String _baseUrl;
  final http.Client _client;
  final GoTrueClient _auth;

  @override
  Future<Result<void>> submit(String note) async {
    final result = await sendAuthorizedRequest(
      _client,
      _auth,
      (accessToken) => http.Request('POST', Uri.parse('$_baseUrl/profile-onboarding/ideal-note'))
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'note': note}),
    );
    return result.when(
      onSuccess: (_) => const Success(null),
      onFailure: (failure) => FailureResult(failure),
    );
  }
}
