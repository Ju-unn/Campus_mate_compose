import 'package:supabase_flutter/supabase_flutter.dart';

/// 시작 화면의 소셜 로그인 공급자. 선언 순서가 버튼 순서다(카카오 → 구글 → 애플).
///
/// 애플은 자리만 둔다 — 개발자 계정 승인 뒤 별도 PR 에서 게이트웨이와 버튼을 붙인다.
enum SocialProvider {
  kakao(OAuthProvider.kakao),
  google(OAuthProvider.google),
  apple(OAuthProvider.apple);

  const SocialProvider(this._oauthProvider);

  final OAuthProvider _oauthProvider;

  /// Supabase `signInWithIdToken(provider:)` 에 넘길 값.
  OAuthProvider toOAuthProvider() => _oauthProvider;
}
