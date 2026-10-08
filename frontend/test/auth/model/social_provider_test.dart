import 'package:campus_mate/auth/model/social_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('버튼 순서는 카카오 → 구글 → 애플이다', () {
    expect(SocialProvider.values, [SocialProvider.kakao, SocialProvider.google, SocialProvider.apple]);
  });

  test('Supabase 의 같은 이름 제공자로 이어진다', () {
    expect(SocialProvider.kakao.toOAuthProvider(), OAuthProvider.kakao);
    expect(SocialProvider.google.toOAuthProvider(), OAuthProvider.google);
    expect(SocialProvider.apple.toOAuthProvider(), OAuthProvider.apple);
  });
}
