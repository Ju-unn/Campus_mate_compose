import 'dart:convert';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/profile/model/avatar_generation_outcome.dart';
import 'package:campus_mate/profile/model/http_avatar_repository.dart';
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

  HttpAvatarRepository buildRepository(Object responseBody) {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode(responseBody),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    return HttpAvatarRepository(ApiClient('https://api.test', client, auth));
  }

  test('ready 응답의 storage_path 를 AvatarReady 로 옮긴다', () async {
    // 서버 router.generate_avatar 가 실제로 보내는 모양 그대로다.
    final repository = buildRepository({
      'status': 'ready',
      'storage_path': '11111111-1111-1111-1111-111111111111/avatar.png',
    });

    final result = await repository.generateAvatar();

    final outcome = result.when(onSuccess: (value) => value, onFailure: (_) => null);
    expect(outcome, isA<AvatarReady>());
    expect(
      (outcome! as AvatarReady).storagePath,
      '11111111-1111-1111-1111-111111111111/avatar.png',
    );
  });

  test('ready 인데 storage_path 가 없으면 기다리지 않고 실패로 돌려준다', () async {
    // 운영 00020: 서버가 {"status": "ready"} 만 보냈고 `as String` 캐스트가 TypeError 를 던졌다.
    // Error 는 Result 밖으로 튀어 "아바타를 만들고 있어요" 화면이 영영 끝나지 않았다 — 실패여야 한다.
    final repository = buildRepository({'status': 'ready'});

    final result = await repository.generateAvatar();

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<UnknownFailure>());
  });
}
