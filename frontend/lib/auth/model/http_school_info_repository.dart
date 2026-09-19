import 'dart:convert';

import 'package:campus_mate/auth/model/department.dart';
import 'package:campus_mate/auth/model/school_info_repository.dart';
import 'package:campus_mate/auth/model/student_number.dart';
import 'package:campus_mate/common/failure.dart';
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
    final response = await http.Response.fromStream(await _client.send(request));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return const Success(null);
    }
    if (response.statusCode == 429) {
      return const FailureResult(RateLimitedFailure());
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return FailureResult(ServerRejectedFailure(body['detail'] as String? ?? '알 수 없는 오류가 발생했습니다'));
  }
}
