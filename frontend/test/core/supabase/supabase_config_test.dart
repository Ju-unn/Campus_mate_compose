import 'dart:convert';

import 'package:campus_mate/core/supabase/supabase_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('url 과 anonKey 가 모두 있으면 설정이 완전하다', () {
    const config = SupabaseConfig(
      url: 'https://example.supabase.co',
      anonKey: 'anon-key',
    );

    expect(config.isComplete(), isTrue);
  });

  test('url 이 비어 있으면 설정이 완전하지 않다', () {
    const config = SupabaseConfig(url: '', anonKey: 'anon-key');

    expect(config.isComplete(), isFalse);
  });

  test('anonKey 가 비어 있으면 설정이 완전하지 않다', () {
    const config = SupabaseConfig(
      url: 'https://example.supabase.co',
      anonKey: '',
    );

    expect(config.isComplete(), isFalse);
  });

  test('공백만 있는 값은 비어 있는 것으로 본다', () {
    const config = SupabaseConfig(url: '   ', anonKey: 'anon-key');

    expect(config.isComplete(), isFalse);
  });

  test('주입값이 없는 테스트 환경에서는 설정이 완전하지 않다', () {
    final config = SupabaseConfig.fromEnvironment();

    expect(config.isComplete(), isFalse);
  });

  // 앱 로그인은 signInWithIdToken 뿐이라 주소로 세션을 받을 일이 없다. 켜 두면 밖에서 만든
  // `kakao…://oauth?code=…` · `#access_token=…` 링크 하나로 남의 세션이 앱에 들어온다(2026-10-18 보안 검사 높음 1).
  test('메인 연결은 딥링크 주소에서 세션을 받지 않는다', () {
    expect(SupabaseConfig.mainAuthOptions.detectSessionInUri, isFalse);
  });

  // 학교 메일 인증용 임시 연결. 메인(소셜) 연결과 같은 url · 키를 쓰되 따로 만든 저장 없는 GoTrueClient 다.
  group('openTemporaryAuth', () {
    const config = SupabaseConfig(url: 'https://project.test', anonKey: 'anon-key');

    test('부를 때마다 새 연결이고 세션 없이 시작한다', () {
      final first = config.openTemporaryAuth();
      final second = config.openTemporaryAuth();
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      expect(identical(first, second), isFalse);
      expect(first.currentSession, isNull);
    });

    test('같은 프로젝트의 /auth/v1 로 익명키를 apikey · Authorization 에 실어 보낸다', () async {
      late http.Request sent;
      final client = MockClient((request) async {
        sent = request;
        return http.Response('{}', 200, headers: {'content-type': 'application/json'});
      });
      final auth = config.openTemporaryAuth(httpClient: client);
      addTearDown(auth.dispose);

      await auth.signInWithOtp(email: 'hong@snu.ac.kr', shouldCreateUser: true);

      expect(sent.url.toString(), startsWith('https://project.test/auth/v1/otp'));
      expect(sent.headers['apikey'], 'anon-key');
      expect(sent.headers['Authorization'], 'Bearer anon-key');
      // implicit flow — PKCE 라면 code_challenge 를 만들어 저장소에 넣으려 한다(저장소가 없다).
      expect((jsonDecode(sent.body) as Map<String, dynamic>)['code_challenge'], isNull);
    });
  });
}
