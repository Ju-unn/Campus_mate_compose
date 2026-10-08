import 'package:campus_mate/auth/model/social_login_repository.dart';
import 'package:campus_mate/auth/model/social_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 공급자 게이트웨이에서 받은 ID 토큰을 Supabase `signInWithIdToken` 으로 세션과 바꾼다.
///
/// 세션이 생기면 `AuthSessionListenable` → 게이트 → 라우터가 다음 화면으로 보낸다 — 여기서 화면을 밀지 않는다.
class SupabaseSocialLoginRepository implements SocialLoginRepository {
  const SupabaseSocialLoginRepository(this._auth, this._gateways);

  final GoTrueClient _auth;

  /// 게이트웨이가 없는 공급자(지금은 애플)는 실패로 끝난다.
  final Map<SocialProvider, IdTokenGateway> _gateways;

  @override
  Future<Result<void>> signIn(SocialProvider provider) async {
    final gateway = _gateways[provider];
    if (gateway == null) {
      return const FailureResult(SocialLoginFailure());
    }
    final credential = await gateway.obtainCredential();
    return credential.when(
      onSuccess: (value) => _exchange(value, provider),
      onFailure: (failure) => FailureResult(failure),
    );
  }

  @override
  Future<void> signOutProviders() async {
    // 게이트웨이마다 실패를 삼키므로 하나가 실패해도 나머지는 계속한다.
    for (final gateway in _gateways.values) {
      await gateway.signOut();
    }
  }

  Future<Result<void>> _exchange(SocialCredential credential, SocialProvider provider) async {
    try {
      await credential.signInTo(_auth, provider);
      return const Success(null);
    } on Object catch (error) {
      // 토큰 · 이메일은 남기지 않는다 — 오류 종류 이름만.
      debugPrint('Supabase 소셜 로그인 실패: ${error.runtimeType}');
      return const FailureResult(SocialLoginFailure());
    }
  }
}
