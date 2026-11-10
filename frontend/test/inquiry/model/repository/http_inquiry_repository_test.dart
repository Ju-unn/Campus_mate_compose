import 'dart:convert';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/inquiry/model/data/inquiry_reason.dart';
import 'package:campus_mate/inquiry/model/repository/http_inquiry_repository.dart';
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

  http.Response jsonResponse(Object body, int status) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<(Result<void>, List<http.Request>)> send(http.Response response) async {
    final seen = <http.Request>[];
    final client = MockClient((request) async {
      seen.add(request);
      return response;
    });
    final result = await HttpInquiryRepository(ApiClient('https://api.test', client, auth)).send(
      reason: InquiryReason.payment,
      body: '하트가 안 들어왔어요',
      replyEmail: 'hello@example.com',
    );
    return (result, seen);
  }

  test('POST /inquiries 에 사유 코드 · 내용 · 답장 받을 메일을 보낸다', () async {
    final (result, seen) = await send(jsonResponse({'ok': true, 'id': 'i1'}, 201));

    expect(result.when(onSuccess: (_) => true, onFailure: (_) => false), isTrue);
    final request = seen.single;
    expect(request.method, 'POST');
    expect(request.url.toString(), 'https://api.test/inquiries');
    expect(request.headers['Authorization'], 'Bearer token-abc');
    expect(jsonDecode(request.body), {
      'reason': 'payment',
      'body': '하트가 안 들어왔어요',
      'reply_email': 'hello@example.com',
    });
  });

  test('429 하루 상한은 RateLimitedFailure 로 돌아온다', () async {
    final (result, _) = await send(jsonResponse({'detail': '오늘은 더 문의할 수 없어요'}, 429));

    expect(result.when(onSuccess: (_) => null, onFailure: (failure) => failure), isA<RateLimitedFailure>());
  });

  test('연결이 끊기면 NetworkFailure 다', () async {
    final client = MockClient((_) async => throw http.ClientException('끊김'));
    final result = await HttpInquiryRepository(ApiClient('https://api.test', client, auth)).send(
      reason: InquiryReason.bug,
      body: '내용',
      replyEmail: 'a@b.co',
    );

    expect(result.when(onSuccess: (_) => null, onFailure: (failure) => failure), isA<NetworkFailure>());
  });
}
