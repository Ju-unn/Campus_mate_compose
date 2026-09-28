import 'dart:convert';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/safety/model/contact_block_repository.dart';
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

  HttpContactBlockRepository buildRepository(http.Client client) {
    return HttpContactBlockRepository(ApiClient('https://api.test', client, auth));
  }

  http.Response jsonResponse(Object body, [int status = 200]) {
    return http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  /// 요청을 붙잡아 두고 [response] 를 돌려주는 가짜 서버.
  (MockClient, List<http.Request>) recording(http.Response response) {
    final seen = <http.Request>[];
    final client = MockClient((request) async {
      seen.add(request);
      return response;
    });
    return (client, seen);
  }

  test('add sends numbers and returns ids in input order with nulls kept', () async {
    final (client, seen) = recording(jsonResponse({
      'blocks': [
        {'id': 'b1', 'created_at': '2026-09-27T00:00:00+00:00'},
        null,
      ],
    }));

    final result = await buildRepository(client).add(['010-1111-2222', '02-123-4567']);

    expect(seen.single.method, 'POST');
    expect(seen.single.url.path, '/contact-blocks');
    expect(seen.single.headers['Authorization'], 'Bearer token-abc');
    expect(jsonDecode(seen.single.body), {
      'numbers': ['010-1111-2222', '02-123-4567'],
    });
    expect(result.when(onSuccess: (ids) => ids, onFailure: (_) => null), ['b1', null]);
  });

  test('add splits into batches of 200 and keeps order', () async {
    final bodies = <List<dynamic>>[];
    final client = MockClient((request) async {
      final numbers = (jsonDecode(request.body) as Map)['numbers'] as List;
      bodies.add(numbers);
      return jsonResponse({
        'blocks': [
          for (final n in numbers) {'id': 'id-$n', 'created_at': '2026-09-27T00:00:00+00:00'},
        ],
      });
    });
    final numbers = [for (var i = 0; i < 450; i++) '010$i'];

    final result = await buildRepository(client).add(numbers);

    expect(bodies.map((b) => b.length), [200, 200, 50]);
    expect(
      result.when(onSuccess: (ids) => ids, onFailure: (_) => null),
      [for (final n in numbers) 'id-$n'],
    );
  });

  test('add stops at the first failed batch', () async {
    // 배치 셋(200 · 200 · 50) 중 가운데가 실패한다 — 멈추지 않으면 셋째를 보내 호출이 3 이 된다.
    var calls = 0;
    final client = MockClient((_) async => ++calls == 2
        ? http.Response('', 503)
        : jsonResponse({'blocks': [for (var i = 0; i < 200; i++) null]}));

    final result = await buildRepository(client).add([for (var i = 0; i < 450; i++) '010$i']);

    expect(result, isA<FailureResult<List<String?>>>());
    expect(calls, 2);
  });

  test('add with no numbers sends nothing', () async {
    final (client, seen) = recording(jsonResponse({'blocks': []}));

    final result = await buildRepository(client).add(const []);

    expect(seen, isEmpty);
    expect(result.when(onSuccess: (ids) => ids, onFailure: (_) => null), isEmpty);
  });

  test('fetch parses id and created_at newest first as given', () async {
    final (client, seen) = recording(jsonResponse({
      'blocks': [
        {'id': 'b2', 'created_at': '2026-09-27T12:00:00+00:00'},
        {'id': 'b1', 'created_at': '2026-09-26T00:00:00+00:00'},
      ],
    }));

    final result = await buildRepository(client).fetch();

    expect(seen.single.method, 'GET');
    expect(seen.single.url.path, '/contact-blocks');
    final blocks = result.when(onSuccess: (blocks) => blocks, onFailure: (_) => <ContactBlock>[]);
    expect(blocks.map((block) => block.id), ['b2', 'b1']);
    expect(blocks.first.createdAt, DateTime.utc(2026, 9, 27, 12).toLocal());
  });

  test('remove calls DELETE /contact-blocks/{id}', () async {
    final (client, seen) = recording(jsonResponse({'ok': true}));

    final result = await buildRepository(client).remove('b1');

    expect(seen.single.method, 'DELETE');
    expect(seen.single.url.path, '/contact-blocks/b1');
    expect(result.when(onSuccess: (_) => true, onFailure: (_) => false), isTrue);
  });
}
