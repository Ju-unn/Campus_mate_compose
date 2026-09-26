import 'dart:convert';
import 'dart:io';

import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/auth/model/http_student_verification_repository.dart';
import 'package:campus_mate/auth/model/real_name.dart';
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
  late Directory tempDir;
  late File photo;
  final realName = RealName.tryParse('홍길동')!;

  setUp(() async {
    auth = MockGoTrueClient();
    final session = MockSession();
    when(() => session.accessToken).thenReturn('token-abc');
    when(() => auth.currentSession).thenReturn(session);
    // 고정 이름을 쓰면 여러 워크트리가 동시에 테스트를 돌릴 때 남의 파일을 지운다 — 실행마다 새 폴더를 만든다.
    tempDir = Directory.systemTemp.createTempSync('student_verification_test');
    photo = File('${tempDir.path}/photo.jpg');
    await photo.writeAsBytes([0xFF, 0xD8, 0xFF]);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  HttpStudentVerificationRepository buildRepository(http.Client client) {
    return HttpStudentVerificationRepository(ApiClient('https://api.test', client, auth));
  }

  test('제출이 성공하면 Success 로 VerificationOutcome 을 돌려준다', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://api.test/student-verification');
      expect(request.headers['Authorization'], 'Bearer token-abc');
      return http.Response(jsonEncode({'status': 'verified'}), 200);
    });

    final result = await buildRepository(client).submit(realName, photo);

    final outcome = result.when(onSuccess: (value) => value, onFailure: (_) => null);
    expect(outcome?.status, 'verified');
    expect(outcome?.rejectReason, isNull);
  });

  test('검토 중 재제출이면 ServerRejectedFailure 에 서버 메시지를 담는다', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'detail': '이미 검토 중이에요'}),
        409,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final result = await buildRepository(client).submit(realName, photo);

    final failure = result.when(onSuccess: (_) => null, onFailure: (f) => f);
    expect(failure, isA<ServerRejectedFailure>());
    expect(failure!.toDisplayMessage(), '이미 검토 중이에요');
  });

  test('요청 한도에 걸리면 RateLimitedFailure', () async {
    final client = MockClient((request) async => http.Response('', 429));

    final result = await buildRepository(client).submit(realName, photo);

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<RateLimitedFailure>());
  });

  test('네트워크 연결이 끊기면 예외가 새지 않고 NetworkFailure', () async {
    final client = MockClient((request) async => throw Exception('연결 실패'));

    final result = await buildRepository(client).submit(realName, photo);

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<NetworkFailure>());
  });

  test('상태 조회가 성공하면 거절 사유를 함께 담는다', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://api.test/me/verification-status');
      return http.Response(
        jsonEncode({'status': 'rejected', 'reject_reason': '사진이 흐려요'}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final result = await buildRepository(client).fetchStatus();

    final outcome = result.when(onSuccess: (value) => value, onFailure: (_) => null);
    expect(outcome?.status, 'rejected');
    expect(outcome?.rejectReason, '사진이 흐려요');
  });
}
