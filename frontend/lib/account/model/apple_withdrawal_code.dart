import 'package:campus_mate/auth/model/apple_login_gateway.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 탈퇴 때 애플 토큰 철회(App Store 5.1.1(v))에 쓸 일회용 authorizationCode 를 받아 온다.
/// 우리는 ID 토큰으로 로그인해 refresh_token 이 없다 — 서버가 이 코드를 토큰으로 바꿔 바로 철회한다.
/// iOS 에서 애플로 가입한 사람(identities 에 apple)에게만 애플 창을 띄운다. 닫거나 실패하면 null 이고 탈퇴는 막지 않는다.
class AppleWithdrawalCode {
  const AppleWithdrawalCode(this._auth, this._apple);

  final GoTrueClient _auth;
  final AppleLoginClient _apple;

  Future<String?> obtain() async {
    if (!_onIos() || !_signedInWithApple()) {
      return null;
    }
    try {
      return await _apple.requestAuthorizationCode();
    } on Object catch (error) {
      // 코드 · 이메일은 남기지 않는다 — 오류 종류 이름만.
      debugPrint('탈퇴 전 애플 재인증 못 함(철회 없이 탈퇴): ${error.runtimeType}');
      return null;
    }
  }

  /// 애플 버튼은 iOS 에서만 그린다(start_view.dart) — 다른 기기에서는 SDK 창을 띄울 수 없다.
  static bool _onIos() => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  bool _signedInWithApple() {
    final identities = _auth.currentUser?.identities ?? const <UserIdentity>[];
    return identities.any((identity) => identity.provider == 'apple');
  }
}

final appleWithdrawalCodeProvider = Provider<AppleWithdrawalCode>((ref) {
  return AppleWithdrawalCode(Supabase.instance.client.auth, const SdkAppleLoginClient());
});
