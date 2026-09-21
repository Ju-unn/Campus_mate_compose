import 'dart:convert';

import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/auth/model/http_verification_gate_repository.dart';
import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSession extends Mock implements Session {}

void main() {
  late MockGoTrueClient auth;

  setUp(() {
    auth = MockGoTrueClient();
    final session = MockSession();
    when(() => session.accessToken).thenReturn('token-abc');
    when(() => auth.currentSession).thenReturn(session);
  });

  HttpVerificationGateRepository buildRepository(http.Client client) {
    return HttpVerificationGateRepository(ApiClient('https://api.test', client, auth));
  }

  Future<VerificationGate?> fetchGateWith(String status, bool hasSchoolInfo) async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://api.test/me/verification-status');
      expect(request.headers['Authorization'], 'Bearer token-abc');
      return http.Response(
        jsonEncode({'status': status, 'has_school_info': hasSchoolInfo}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final result = await buildRepository(client).fetchGate();
    return result.when(onSuccess: (value) => value, onFailure: (_) => null);
  }

  test('학생증 인증 전이면 needsStudentVerification', () async {
    final gate = await fetchGateWith('pending', false);

    expect(gate, VerificationGate.needsStudentVerification);
  });

  test('인증은 됐지만 학교 정보가 없으면 needsSchoolInfo', () async {
    final gate = await fetchGateWith('verified', false);

    expect(gate, VerificationGate.needsSchoolInfo);
  });

  test('인증과 학교 정보가 모두 끝나면 complete', () async {
    final gate = await fetchGateWith('verified', true);

    expect(gate, VerificationGate.complete);
  });

  test('네트워크 연결이 끊기면 예외가 새지 않고 NetworkFailure', () async {
    final client = MockClient((request) async => throw Exception('연결 실패'));

    final result = await buildRepository(client).fetchGate();

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<NetworkFailure>());
  });
}
