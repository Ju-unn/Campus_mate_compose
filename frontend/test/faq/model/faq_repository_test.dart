import 'dart:convert';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/faq/model/faq_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  SupabaseFaqRepository repositoryAnswering(Object body) => SupabaseFaqRepository(
    SupabaseClient(
      'https://example.supabase.co',
      'anon',
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
          request: request,
        ),
      ),
    ),
  );

  test('행을 읽어 FaqItem 으로', () async {
    final result = await repositoryAnswering([
      {'id': 'c1', 'category': 'card_matching', 'question': '카드는 언제 오나요?', 'answer': '아침 7시', 'sort_order': 10},
    ]).fetchAll();
    expect(result.when(onSuccess: (items) => items.single.question, onFailure: (f) => f), '카드는 언제 오나요?');
  });

  test('행 모양이 깨져도(형 변환 오류) 던지지 않고 실패로 — 부르는 쪽이 캐시로 넘어간다', () async {
    final result = await repositoryAnswering([
      {'id': 'c1', 'category': 'card_matching', 'question': null, 'answer': '아침 7시', 'sort_order': 10},
    ]).fetchAll();
    expect(result.when(onSuccess: (items) => items, onFailure: (f) => f), isA<NetworkFailure>());
  });
}
