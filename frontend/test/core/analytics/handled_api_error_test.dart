import 'dart:async';
import 'dart:io';

import 'package:campus_mate/core/analytics/handled_api_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final url = Uri.parse('https://api.test/chat/matches/11111111-1111-4111-8111-111111111111/messages?limit=1');

  test('예외는 타입 이름만 남기고 메시지 · 주소는 버린다', () {
    final error = HandledApiError.fromException(
      SocketException('Connection refused (OS Error) 10.0.0.7:443', address: InternetAddress.loopbackIPv4),
      url,
    );

    expect(error.kind, 'SocketException');
    expect(error.status, isNull);
    expect(error.route, '/chat/matches/:id/messages');
    expect(error.toString(), isNot(contains('10.0.0.7')));
    expect(error.toString(), isNot(contains('refused')));
  });

  test('시간 초과는 TimeoutException', () {
    final error = HandledApiError.fromException(TimeoutException('15초가 지났어요', const Duration(seconds: 15)), url);

    expect(error.kind, 'TimeoutException');
    expect(error.toString(), isNot(contains('15초')));
  });

  test('서버 오류는 상태 코드와 경로 패턴만 든다', () {
    final error = HandledApiError.fromStatus(503, url);

    expect(error.kind, 'ServerError');
    expect(error.status, 503);
    expect(error.route, '/chat/matches/:id/messages');
    expect(error.toString(), 'HandledApiError(kind: ServerError, status: 503, route: /chat/matches/:id/messages)');
  });

  test('타입 이름은 영문자 · 숫자 · 밑줄만 남기고 40자에서 자른다', () {
    final error = HandledApiError.fromException(_Odd<List<int>>(), url);

    expect(error.kind, matches(RegExp(r'^[A-Za-z0-9_]{1,40}$')), reason: '제네릭 꺾쇠 같은 글자는 빠진다');
  });

  test('같은 종류 · 상태 · 경로는 같은 열쇠, 다르면 다른 열쇠', () {
    final a = HandledApiError.fromStatus(500, url);
    final b = HandledApiError.fromStatus(500, Uri.parse('https://api.test/chat/matches/22222222-2222-4222-8222-222222222222/messages'));
    final c = HandledApiError.fromStatus(502, url);

    expect(a.key, b.key, reason: 'id 만 다른 같은 길은 같은 오류로 센다');
    expect(a.key, isNot(c.key));
  });
}

class _Odd<T> implements Exception {}
