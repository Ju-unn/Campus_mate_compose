import 'dart:convert';

import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/auth/model/department.dart';
import 'package:campus_mate/auth/model/http_school_info_repository.dart';
import 'package:campus_mate/auth/model/student_number.dart';
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
  final department = Department.tryParse('컴퓨터공학과')!;
  final studentNumber = StudentNumber.tryParse('20240001')!;

  setUp(() {
    auth = MockGoTrueClient();
    final session = MockSession();
    when(() => session.accessToken).thenReturn('token-abc');
    when(() => auth.currentSession).thenReturn(session);
  });

  HttpSchoolInfoRepository buildRepository(http.Client client) {
    return HttpSchoolInfoRepository(ApiClient('https://api.test', client, auth));
  }

  test('제출이 성공하면 Success 를 돌려준다', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://api.test/school-info');
      expect(request.method, 'POST');
      expect(request.headers['Authorization'], 'Bearer token-abc');
      expect(
        jsonDecode(request.body),
        {'department': '컴퓨터공학과', 'student_number': '20240001'},
      );
      return http.Response('', 200);
    });

    final result = await buildRepository(client).submit(department, studentNumber);

    expect(result.when(onSuccess: (_) => true, onFailure: (_) => false), isTrue);
  });

  test('이미 제출한 정보면 ServerRejectedFailure 에 서버 메시지를 담는다', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'detail': '이미 제출한 정보예요'}),
        409,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final result = await buildRepository(client).submit(department, studentNumber);

    final failure = result.when(onSuccess: (_) => null, onFailure: (f) => f);
    expect(failure, isA<ServerRejectedFailure>());
    expect(failure!.toDisplayMessage(), '이미 제출한 정보예요');
  });

  test('요청 한도에 걸리면 RateLimitedFailure', () async {
    final client = MockClient((request) async => http.Response('', 429));

    final result = await buildRepository(client).submit(department, studentNumber);

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<RateLimitedFailure>());
  });

  test('서버 내부 오류(5xx)는 문구를 지어내지 않고 UnknownFailure', () async {
    final client = MockClient((request) async => http.Response('<html>500</html>', 500));

    final result = await buildRepository(client).submit(department, studentNumber);

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<UnknownFailure>());
  });

  test('네트워크 연결이 끊기면 예외가 새지 않고 NetworkFailure', () async {
    final client = MockClient((request) async => throw Exception('연결 실패'));

    final result = await buildRepository(client).submit(department, studentNumber);

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<NetworkFailure>());
  });
}
