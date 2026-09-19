import 'dart:convert';
import 'dart:io';

import 'package:campus_mate/auth/model/http_send.dart';
import 'package:campus_mate/auth/model/real_name.dart';
import 'package:campus_mate/auth/model/student_verification_repository.dart';
import 'package:campus_mate/common/result.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// [StudentVerificationRepository]를 FastAPI 호출로 구현한다.
class HttpStudentVerificationRepository implements StudentVerificationRepository {
  const HttpStudentVerificationRepository(this._baseUrl, this._client, this._auth);

  final String _baseUrl;
  final http.Client _client;
  final GoTrueClient _auth;

  @override
  Future<Result<VerificationOutcome>> submit(RealName realName, File photo) async {
    final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/student-verification'))
      ..headers['Authorization'] = 'Bearer ${_auth.currentSession!.accessToken}'
      ..fields['real_name'] = realName.toRequestValue()
      ..files.add(await http.MultipartFile.fromPath('photo', photo.path));
    return _send(request);
  }

  @override
  Future<Result<VerificationOutcome>> fetchStatus() async {
    final request = http.Request('GET', Uri.parse('$_baseUrl/me/verification-status'))
      ..headers['Authorization'] = 'Bearer ${_auth.currentSession!.accessToken}';
    return _send(request);
  }

  Future<Result<VerificationOutcome>> _send(http.BaseRequest request) async {
    final result = await sendHttpRequest(_client, request);
    return result.when(
      onSuccess: (response) => Success(_toOutcome(response)),
      onFailure: (failure) => FailureResult(failure),
    );
  }

  VerificationOutcome _toOutcome(http.Response response) {
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return VerificationOutcome(status: body['status'] as String, rejectReason: body['reject_reason'] as String?);
  }
}
