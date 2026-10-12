import 'package:supabase_flutter/supabase_flutter.dart';

/// 시작 화면의 소셜 로그인 공급자. 선언 순서가 버튼 순서다(카카오 → 구글 → 애플).
///
/// 애플은 iOS 에서만 버튼을 그린다(start_view.dart). 안드로이드는 카카오 · 구글 둘.
enum SocialProvider {
  kakao(OAuthProvider.kakao),
  google(OAuthProvider.google),
  apple(OAuthProvider.apple);

  const SocialProvider(this._oauthProvider);

  final OAuthProvider _oauthProvider;

  /// Supabase `signInWithIdToken(provider:)` 에 넘길 값.
  OAuthProvider toOAuthProvider() => _oauthProvider;
}
