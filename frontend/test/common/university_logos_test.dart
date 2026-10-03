import 'dart:convert';

import 'package:campus_mate/common/university_logos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late Uri requested;

  SupabaseClient clientAnswering(Object body) => SupabaseClient(
    'https://example.supabase.co',
    'anon',
    httpClient: MockClient((request) async {
      requested = request.url;
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
        request: request,
      );
    }),
  );

  test('universities 의 이름 · logo_path 를 읽어 이름 → 공개 버킷 주소로', () async {
    final logos = await fetchUniversityLogos(
      clientAnswering([
        {'name': '서울대학교', 'logo_path': 'uni-75ee0c4a522d491b.webp'},
      ]),
    );

    expect(requested.path, '/rest/v1/universities');
    expect(requested.queryParameters['select'], 'name,logo_path');
    expect(logos, {
      '서울대학교': 'https://example.supabase.co/storage/v1/object/public/university-logos/uni-75ee0c4a522d491b.webp',
    });
  });

  test('logo_path 가 없는 학교(테스트대학)는 빠진다 — 학교 줄이 이름만 그린다', () async {
    final logos = await fetchUniversityLogos(
      clientAnswering([
        {'name': '테스트대학', 'logo_path': null},
      ]),
    );

    expect(logos, isEmpty);
  });
}
