import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase 인증 상태가 바뀔 때마다 [notifyListeners] 를 호출해
/// go_router 가 redirect 를 다시 계산하게 한다.
class AuthSessionListenable extends ChangeNotifier {
  AuthSessionListenable(SupabaseClient client) : _auth = client.auth {
    _subscription = _auth.onAuthStateChange.listen((_) => notifyListeners());
  }

  final GoTrueClient _auth;
  late final StreamSubscription<AuthState> _subscription;

  bool get isAuthenticated => _auth.currentSession != null;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
