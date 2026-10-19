import 'dart:async';

import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// [AdminAuth] 의 Supabase 구현.
class SupabaseAdminAuth implements AdminAuth {
  SupabaseAdminAuth(this._auth) {
    // gotrue 의 onAuthStateChange 는 ReplaySubject 라 새로 듣는 쪽마다 지난 사건을 처음부터 다시 받는다.
    // 관문이 다시 만들어질 때마다 직접 들으면 다시 받은 사건이 또 관문을 깨워 끝없이 돈다 — 여기서 한 번만 듣고 넘긴다.
    _subscription = _auth.onAuthStateChange.listen(
      (state) {
        if (_gateEvents.contains(state.event)) _changes.add(null);
      },
      onError: (Object _) {},
    );
  }

  final GoTrueClient _auth;
  final StreamController<void> _changes = StreamController<void>.broadcast();
  late final StreamSubscription<AuthState> _subscription;

  /// 토큰 갱신(tokenRefreshed)은 뺀다 — mfaState 가 세션을 새로 받을 때마다 나와서 관문이 다시 돌게 된다.
  static const Set<AuthChangeEvent> _gateEvents = {
    AuthChangeEvent.signedIn,
    AuthChangeEvent.signedOut,
    AuthChangeEvent.mfaChallengeVerified,
  };

  /// 인증 앱 목록에 보이는 이름(QR 없이 직접 넣으면 쓰이지 않지만 등록 기록에 남는다)
  static const String _issuer = 'CampusMate Admin';

  @override
  bool get hasSession => _auth.currentSession != null;

  @override
  String? get accessToken => _auth.currentSession?.accessToken;

  @override
  String? get email => _auth.currentUser?.email;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> signInWithGoogle() async {
    // 웹은 같은 탭(_self)에서 구글로 갔다가 이 주소로 돌아온다. 계정 고르기를 늘 띄워
    // "다른 계정으로 로그인"(권한 없음 화면)이 브라우저에 남은 구글 계정으로 그냥 다시 들어가지 않게 한다.
    await _auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: Uri.base.origin,
      queryParams: const {'prompt': 'select_account'},
    );
  }

  @override
  Future<MfaState> mfaState() async {
    // listFactors 는 세션을 새로 받아 온다 — 다른 브라우저에서 등록한 TOTP 도 보인다.
    final factors = await _auth.mfa.listFactors();
    final level = _auth.mfa.getAuthenticatorAssuranceLevel().currentLevel;
    return MfaState(
      aal2: level == AuthenticatorAssuranceLevels.aal2,
      factorId: factors.totp.isEmpty ? null : factors.totp.first.id,
    );
  }

  @override
  Future<TotpEnrollment> enrollTotp() async {
    // 새로고침 · 창 닫기로 확인하지 못한 등록이 남아 있으면 지운다 — 쌓이면 다음 등록이 거절될 수 있다.
    final factors = await _auth.mfa.listFactors();
    final stale = factors.all.where((f) => f.factorType == FactorType.totp && f.status == FactorStatus.unverified);
    for (final factor in stale) {
      await _auth.mfa.unenroll(factor.id);
    }
    final response = await _auth.mfa.enroll(factorType: FactorType.totp, issuer: _issuer);
    return TotpEnrollment(factorId: response.id, secret: response.totp!.secret);
  }

  @override
  Future<VerifyOutcome> verifyTotp({required String factorId, required String code}) async {
    try {
      await _auth.mfa.challengeAndVerify(factorId: factorId, code: code);
      return VerifyOutcome.ok;
    } on AuthRetryableFetchException {
      return VerifyOutcome.failed;
    } on AuthException {
      return VerifyOutcome.wrongCode;
    } on Exception {
      return VerifyOutcome.failed;
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  void dispose() {
    _subscription.cancel();
    _changes.close();
  }
}

/// 처음 연 주소를 Supabase 가 로그인 복귀로 보고 세션으로 바꿀지 정한다(main.dart 의 detectSessionInUriPredicate).
/// 우리 웹은 PKCE 만 쓴다 — 쿼리의 `?code=`(성공) · `?error=`(실패 · 취소)만 넘긴다. 기본 판정은 `#access_token=` 조각도
/// 받아들여, 남이 만든 링크를 누르면 세션이 그 사람 계정으로 바뀔 수 있다(보안 검토 10-18 낮음 7).
/// `?code=x#access_token=…` 처럼 섞여도 gotrue getSessionFromUrl 이 error → code 순으로 먼저 처리해
/// access_token 갈래까지 가지 않는다(gotrue 2.27.3 gotrue_client.dart getSessionFromUrl).
bool isPkceAuthCallback(Uri uri) {
  final query = uri.queryParameters;
  return query.containsKey('code') || query.containsKey('error');
}
