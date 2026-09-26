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

  /// 서버가 실제로 보내는 본문 모양 그대로 먹인다(router.py `_avatar_status`) — 계약이 어긋나면
  /// 그 길에서만 캐스트가 터진다(운영 00020 무한 로딩). 등록과 상태 조회가 **같은 파서**를 쓴다.
  Future<AvatarGenerationOutcome?> outcomeOf(Object body, {bool status = false}) async {
    final repository = buildRepository(body);
    final result = status ? await repository.fetchAvatarStatus() : await repository.generateAvatar();
    return result.when(onSuccess: (value) => value, onFailure: (_) => null);
  }

  test('등록 응답의 pending 을 AvatarPending 으로 옮긴다', () async {
    expect(await outcomeOf({'status': 'pending'}), isA<AvatarPending>());
  });

  test('avatar_url 만 실린 ready 본문을 AvatarReady 로 옮긴다', () async {
    // 뜻이 저장 경로에서 **전체 주소**로 바뀌었다 — 서버가 버킷 접두사까지 붙여서 준다.
    const url = 'https://x.supabase.co/storage/v1/object/public/avatars/aa/avatar.png';
    final outcome = await outcomeOf(
      {'status': 'ready', 'avatar_url': url, 'compensation_hearts': null},
      status: true,
    );

    expect(outcome, isA<AvatarReady>());
    expect((outcome! as AvatarReady).avatarUrl, url);
  });

  test('fallback 본문에서 그림 주소와 서버가 준 하트 수를 같이 읽는다', () async {
    // 하트 수를 앱 상수로 굳히면 서버 규칙이 바뀔 때 앱만 거짓말을 한다.
    const url = 'https://x.supabase.co/storage/v1/object/public/avatars/aa/fallback.png';
    final outcome = await outcomeOf(
      {'status': 'fallback', 'avatar_url': url, 'compensation_hearts': 10},
    );

    expect(outcome, isA<AvatarFallback>());
    expect((outcome! as AvatarFallback).avatarUrl, url);
    expect((outcome as AvatarFallback).compensationHearts, 10);
  });

  test('한 번도 만든 적 없는 none 은 실패와 같게 다룬다', () async {
    // 여기서 작업을 자동 등록하지 않는다 — 화면이 "다시 만들기" 를 띄운다(서버도 안 한다).
    final outcome = await outcomeOf(
      {'status': 'none', 'avatar_url': null, 'compensation_hearts': null},
      status: true,
    );

    expect(outcome, isA<AvatarFailed>());
  });

  test('ready 인데 그림 주소가 없으면 기다리지 않고 실패로 돌려준다', () async {
    // 운영 00020: 서버가 {"status": "ready"} 만 보냈고 `as String` 캐스트가 TypeError 를 던졌다.
    // Error 는 Result 밖으로 튀어 "아바타를 만들고 있어요" 화면이 영영 끝나지 않았다 — 실패여야 한다.
    final repository = buildRepository({'status': 'ready'});

    final result = await repository.generateAvatar();

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<UnknownFailure>());
  });
}
