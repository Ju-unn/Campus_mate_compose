import 'package:campus_mate/auth/model/login_nonce.dart';
import 'package:campus_mate/auth/model/social_provider.dart';
import 'package:campus_mate/common/result.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 시작 화면의 소셜 로그인. 성공하면 Supabase 세션이 생기고, 이동은 세션 리스너 → 게이트 → 라우터가 맡는다.
///
/// 실패는 [LoginCancelledFailure](사용자 취소)와 [SocialLoginFailure](그 밖의 모든 실패) 둘뿐이다.
/// 계정 이메일은 읽지도 쓰지도 않는다 — 학교 메일 인증은 별도 단계(지시문 08)다.
abstract interface class SocialLoginRepository {
  Future<Result<void>> signIn(SocialProvider provider);
}

/// 공급자 SDK 에서 ID 토큰을 받아 오는 쪽. 카카오 · 구글 SDK 를 이 뒤에 숨겨 시험에서 가짜로 바꾼다.
abstract interface class IdTokenGateway {
  /// 취소면 [LoginCancelledFailure], 그 밖의 실패는 [SocialLoginFailure].
  Future<Result<SocialCredential>> obtainCredential();
}

/// 공급자가 준 ID 토큰과, 그 토큰에 해시로 실린 원본 nonce 한 쌍.
class SocialCredential {
  const SocialCredential(this._idToken, this._nonce);

  final String _idToken;
  final LoginNonce _nonce;

  /// 공급자 SDK 에 준 해시가 이 자격의 원본 nonce 에서 나온 것인지.
  bool isBoundTo(String hashedNonce) => _nonce.forProvider() == hashedNonce;

  /// Supabase 에는 해시가 아니라 **원본** nonce 를 준다([LoginNonce] 주석).
  Future<AuthResponse> signInTo(GoTrueClient auth, SocialProvider provider) {
    return auth.signInWithIdToken(
      provider: provider.toOAuthProvider(),
      idToken: _idToken,
      nonce: _nonce.forSupabase(),
    );
  }
}
