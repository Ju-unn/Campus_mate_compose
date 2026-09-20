import 'dart:async';
import 'dart:convert';

import 'package:campus_mate/auth/model/http_send.dart';
import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/auth/model/verification_gate_repository.dart';
import 'package:campus_mate/common/result.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// [VerificationGateRepository]를 FastAPI 호출로 구현한다.
class HttpVerificationGateRepository implements VerificationGateRepository {
  const HttpVerificationGateRepository(this._baseUrl, this._client, this._auth);

  final String _baseUrl;
  final http.Client _client;
  final GoTrueClient _auth;

  @override
  Future<Result<VerificationGate>> fetchGate() async {
    return _send((accessToken) => http.Request('GET', Uri.parse('$_baseUrl/me/verification-status'))
      ..headers['Authorization'] = 'Bearer $accessToken');
  }

  Future<Result<VerificationGate>> _send(
    FutureOr<http.BaseRequest> Function(String accessToken) buildRequest,
  ) async {
    final result = await sendAuthorizedRequest(_client, _auth, buildRequest);
    return result.when(
      onSuccess: (response) => Success(_toGate(response)),
      onFailure: (failure) => FailureResult(failure),
    );
  }

  VerificationGate _toGate(http.Response response) {
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return _toGateFrom(body['status'] as String, body['has_school_info'] as bool);
  }

  VerificationGate _toGateFrom(String status, bool hasSchoolInfo) {
    if (status != 'verified') {
      return VerificationGate.needsStudentVerification;
    }
    if (!hasSchoolInfo) {
      return VerificationGate.needsSchoolInfo;
    }
    return VerificationGate.complete;
  }
}
