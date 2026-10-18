import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase 인증 상태가 바뀔 때마다 [notifyListeners] 를 호출해
/// go_router 가 redirect 를 다시 계산하게 한다.
class AuthSessionListenable extends ChangeNotifier {
  AuthSessionListenable(SupabaseClient client) : _auth = client.auth {
    // 갱신 실패 같은 오류도 이 스트림으로 온다 — 받을 곳이 없으면 앱 전체의 처리 안 된 오류가 된다.
    // 삼키고 알리지 않는다: 세션이 정말 끝났으면 gotrue 가 signedOut 을 따로 보낸다.
    // Supabase 자체 구독과 별개로 앱 구독도 오류를 받아야 처리 안 된 예외가 안 남는다(구독마다 따로 전달된다).
    _subscription = _auth.onAuthStateChange.listen((_) => notifyListeners(), onError: (Object _) {});
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
