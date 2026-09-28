import 'dart:convert';
import 'dart:io';

import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/model/http_heart_task_repository.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSession extends Mock implements Session {}

Map<String, Object?> _task(String code, String state, {int reward = 25, int limit = 3, String? reason}) => {
      'task': code,
      'reward_hearts': reward,
      'state': state,
      'used': 0,
      'limit': limit,
      'reject_reason': reason,
    };

void main() {
  late MockGoTrueClient auth;
  late Directory tempDir;
  late File photo;

  setUp(() async {
    auth = MockGoTrueClient();
    final session = MockSession();
    when(() => session.accessToken).thenReturn('token-abc');
    when(() => auth.currentSession).thenReturn(session);
    tempDir = Directory.systemTemp.createTempSync('heart_task_test');
    photo = File('${tempDir.path}/proof.jpg');
    await photo.writeAsBytes([0xFF, 0xD8, 0xFF]);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  HttpHeartTaskRepository build(http.Client client) => HttpHeartTaskRepository(ApiClient('https://api.test', client, auth));

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

  test('목록은 GET /heart-tasks 의 세 줄을 순서대로 읽는다', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://api.test/heart-tasks');
      expect(request.headers['Authorization'], 'Bearer token-abc');
      return json({
        'tasks': [
          _task('everytime_post', 'reviewing', reward: 50, limit: 1),
          _task('kakao_share', 'done'),
          _task('poll_vote', 'open', reward: 10),
        ],
      });
    });

    final result = await build(client).fetchTasks();

    final tasks = result.when(onSuccess: (tasks) => tasks, onFailure: (_) => <HeartTask>[]);
    expect(tasks.map((task) => task.kind), HeartTaskKind.values);
    expect(tasks.map((task) => task.state), [HeartTaskState.reviewing, HeartTaskState.done, HeartTaskState.open]);
  });

  test('제출은 항목 경로로 photo 칸 multipart 를 보내고 새 줄을 돌려준다', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://api.test/heart-tasks/kakao_share/submissions');
      expect(request.headers['content-type'], startsWith('multipart/form-data'));
      // 본문에 JPEG 바이트(0xFF)가 섞여 utf8 로는 못 읽는다.
      expect(latin1.decode(request.bodyBytes), contains('name="photo"'));
      return json({'task': _task('kakao_share', 'reviewing')}, 201);
    });

    final result = await build(client).submit(HeartTaskKind.kakaoShare, photo);

    expect(result.when(onSuccess: (task) => task.state, onFailure: (_) => null), HeartTaskState.reviewing);
  });

  test('월 한도 429 는 RateLimitedFailure 로 온다 — 문구는 ViewModel 이 바꾼다', () async {
    final client = MockClient((request) async => json({'detail': '이번 달에는 더 인증할 수 없어요'}, 429));

    final result = await build(client).submit(HeartTaskKind.everytimePost, photo);

    expect(result.when(onSuccess: (_) => null, onFailure: (failure) => failure), isA<RateLimitedFailure>());
  });

  test('검수 중 409 는 서버 문구를 그대로 보여 준다', () async {
    final client = MockClient((request) async => json({'detail': '이미 확인 중이에요, 결과를 기다려 주세요'}, 409));

    final result = await build(client).submit(HeartTaskKind.everytimePost, photo);

    expect(
      result.when(onSuccess: (_) => '', onFailure: (failure) => failure.toDisplayMessage()),
      '이미 확인 중이에요, 결과를 기다려 주세요',
    );
  });

  test('201 인데 본문 모양이 다르면 알 수 없는 오류다(예외가 Result 밖으로 튀지 않는다)', () async {
    final client = MockClient((request) async => json({'unexpected': true}, 201));

    final result = await build(client).submit(HeartTaskKind.kakaoShare, photo);

    expect(result.when(onSuccess: (_) => null, onFailure: (failure) => failure), isA<UnknownFailure>());
  });
}
