import 'package:campus_mate/auth/model/google_login_gateway.dart';
import 'package:campus_mate/auth/model/kakao_login_gateway.dart';
import 'package:campus_mate/auth/model/social_login_repository.dart';
import 'package:campus_mate/auth/model/social_provider.dart';
import 'package:campus_mate/auth/model/supabase_social_login_repository.dart';
import 'package:campus_mate/core/env.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 게이트웨이는 provider 가 아니라 **최상위**에 둔다. 로그아웃하면 `SessionScope` 가 ProviderScope 를 새로 만드는데,
/// `GoogleSignIn.instance` 는 앱 프로세스에 하나라 `initialize` 를 다시 부르면 안 된다(v7 규칙).
/// 최상위 값은 처음 읽을 때 만들어져 프로세스가 끝날 때까지 남는다.
final Map<SocialProvider, IdTokenGateway> _gateways = {
  SocialProvider.kakao: const KakaoLoginGateway(SdkKakaoLoginClient(Env.kakaoNativeAppKey)),
  SocialProvider.google: GoogleLoginGateway(const SdkGoogleLoginClient(Env.googleWebClientId)),
};

final socialLoginRepositoryProvider = Provider<SocialLoginRepository>((ref) {
  return SupabaseSocialLoginRepository(Supabase.instance.client.auth, _gateways);
});
