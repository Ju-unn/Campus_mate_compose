import 'dart:async';

import 'package:campus_mate/core/supabase/auth_session_listenable.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _MockSession extends Mock implements Session {}

/// 실제 Supabase 없이 [AuthSessionListenable] 을 만든다. [signIn] · [signOut] 으로 세션을 바꾸면 리스너에 알린다.
class FakeAuthSession {
  FakeAuthSession({bool signedIn = false}) : _session = signedIn ? _MockSession() : null {
    when(() => _client.auth).thenReturn(_auth);
    when(() => _auth.currentSession).thenAnswer((_) => _session);
    when(() => _auth.onAuthStateChange).thenAnswer((_) => _changes.stream);
    listenable = AuthSessionListenable(_client);
  }

  final _client = _MockSupabaseClient();
  final _auth = _MockGoTrueClient();
  final _changes = StreamController<AuthState>.broadcast(sync: true);
  Session? _session;
  late final AuthSessionListenable listenable;

  void signIn() {
    _session = _MockSession();
    _changes.add(AuthState(AuthChangeEvent.signedIn, _session));
  }

  void signOut() {
    _session = null;
    _changes.add(const AuthState(AuthChangeEvent.signedOut, null));
  }

  Future<void> dispose() => _changes.close();
}
