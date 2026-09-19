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
}
