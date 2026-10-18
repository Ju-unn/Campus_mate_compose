import 'dart:async';

import 'package:campus_mate/core/supabase/auth_session_listenable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSession extends Mock implements Session {}

void main() {
  late MockSupabaseClient client;
  late MockGoTrueClient auth;
  late StreamController<AuthState> authStateController;

  setUp(() {
    client = MockSupabaseClient();
    auth = MockGoTrueClient();
    authStateController = StreamController<AuthState>.broadcast();
    when(() => client.auth).thenReturn(auth);
    when(() => auth.onAuthStateChange).thenAnswer((_) => authStateController.stream);
  });

  tearDown(() => authStateController.close());

  test('세션이 없으면 isAuthenticated 는 false', () {
    when(() => auth.currentSession).thenReturn(null);
    final listenable = AuthSessionListenable(client);
    addTearDown(listenable.dispose);

    expect(listenable.isAuthenticated, isFalse);
  });

  test('세션이 있으면 isAuthenticated 는 true', () {
    when(() => auth.currentSession).thenReturn(MockSession());
    final listenable = AuthSessionListenable(client);
    addTearDown(listenable.dispose);

    expect(listenable.isAuthenticated, isTrue);
  });

  test('인증 상태가 바뀌면 리스너에 알린다', () async {
    when(() => auth.currentSession).thenReturn(null);
    final listenable = AuthSessionListenable(client);
    addTearDown(listenable.dispose);
    var notified = false;
    listenable.addListener(() => notified = true);

    authStateController.add(AuthState(AuthChangeEvent.signedIn, MockSession()));
    await Future<void>.delayed(Duration.zero);

    expect(notified, isTrue);
  });

  // gotrue 는 토큰 갱신 실패 등을 이 스트림에 오류로도 흘린다. 받을 곳이 없으면 앱 전체의 처리 안 된 오류가 된다 —
  // 삼키고 상태는 그대로 둔다(세션 판단은 currentSession 이 한다, 2026-10-18 보안 검사 낮음 4).
  test('인증 스트림 오류는 삼키고, 그 뒤 이벤트도 계속 알린다', () async {
    when(() => auth.currentSession).thenReturn(MockSession());
    final listenable = AuthSessionListenable(client);
    addTearDown(listenable.dispose);
    var notified = 0;
    listenable.addListener(() => notified++);

    authStateController.addError(AuthException('refresh failed'));
    await Future<void>.delayed(Duration.zero);

    expect(notified, 0);
    expect(listenable.isAuthenticated, isTrue);

    authStateController.add(AuthState(AuthChangeEvent.tokenRefreshed, MockSession()));
    await Future<void>.delayed(Duration.zero);

    expect(notified, 1);
  });
}
