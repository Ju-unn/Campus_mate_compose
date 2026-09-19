import 'dart:convert';

import 'package:campus_mate/auth/model/department.dart';
import 'package:campus_mate/auth/model/http_send.dart';
import 'package:campus_mate/auth/model/school_info_repository.dart';
import 'package:campus_mate/auth/model/student_number.dart';
import 'package:campus_mate/common/result.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// [SchoolInfoRepository]를 FastAPI 호출로 구현한다.
class HttpSchoolInfoRepository implements SchoolInfoRepository {
  const HttpSchoolInfoRepository(this._baseUrl, this._client, this._auth);

  final String _baseUrl;
  final http.Client _client;
  final GoTrueClient _auth;

  @override
  Future<Result<void>> submit(Department department, StudentNumber studentNumber) async {
    final request = http.Request('POST', Uri.parse('$_baseUrl/school-info'))
      ..headers['Authorization'] = 'Bearer ${_auth.currentSession!.accessToken}'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'department': department.toRequestValue(),
        'student_number': studentNumber.toRequestValue(),
      });
    return _send(request);
  }

  Future<Result<void>> _send(http.BaseRequest request) async {
    final result = await sendHttpRequest(_client, request);
    return result.when(
      onSuccess: (_) => const Success(null),
      onFailure: (failure) => FailureResult(failure),
    );
  }
}
