import 'package:campus_mate/auth/model/social_login_repository.dart';
import 'package:campus_mate/auth/model/social_login_repository_provider.dart';
import 'package:campus_mate/core/push/push_provider.dart';
import 'package:campus_mate/core/push/push_registrar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 로그아웃은 반드시 여기를 지난다.
///
/// `signOut()` 을 먼저 부르면 세션이 사라진 뒤에야 [PushRegistrar.stop] 이 불린다.
/// 그 안의 `DELETE /cards/push-tokens/{token}` 은 실어 보낼 토큰이 없어 401 로 끝나고,
/// 이 기기의 FCM 토큰은 서버에 그대로 남는다 — 다음으로 로그인한 사람이 덮어쓸 때까지
/// 죽은 토큰이 쌓인다. 그래서 지우고 나서 나간다.
///
/// `auth.signOut()` 은 이 기기의 세션을 먼저 지우고 나서 서버에 알린다(gotrue 2.27 `_signOut`).
/// 서버 알림이 네트워크 오류로 던져도 이 기기는 이미 로그아웃이고 토큰도 버렸다 — 화면까지 올리지 않는다.
///
/// 토큰 정리가 던져도 로그아웃은 한다(finally). 탈퇴 리스너는 상태가 바뀔 때 한 번만 부르고 auth_redirect 는
/// 그동안 제자리라, 여기서 건너뛰면 앱을 다시 켜기 전에는 다시 시도할 길이 없다. (로그인 만료는 대개 gotrue 가
/// refresh 실패 때 세션을 이미 지워 안 갇힌다 — refresh 응답에 세션이 없는 드문 경우만 여기에 기댄다.)
/// 정리 오류는 로그아웃 뒤 그대로 던진다 — 숨기지 않는다.
///
/// 앱 로그아웃 직후 [social] 로 카카오 · 구글 SDK 로그인도 끊는다(후속 지시문 13 B-1). 탈퇴도 main.dart 의
/// 리스너가 이 함수를 지나므로 같이 적용된다. 공급자 쪽 실패는 앱 로그아웃에 영향을 주지 않는다.
Future<void> signOut(PushRegistrar registrar, GoTrueClient auth, {SocialLoginRepository? social}) async {
  try {
    await registrar.stop();
  } finally {
    try {
      await auth.signOut();
    } on AuthException {
      // 위 주석 — 남은 것은 서버 쪽 알림뿐이다.
    }
    await _signOutProviders(social);
  }
}

Future<void> _signOutProviders(SocialLoginRepository? social) async {
  try {
    await social?.signOutProviders();
  } on Object catch (error) {
    debugPrint('소셜 공급자 로그아웃 실패: ${error.runtimeType}');
  }
}

/// 설정 16g 가 부르는 로그아웃. 테스트는 덮어써 Supabase 를 켜지 않는다.
/// registrar 는 main.dart 가 [PushRegistrar.start] 한 그 인스턴스여야 등록한 토큰을 지운다 — 같은 provider 에서 읽는다.
final signOutProvider = Provider<Future<void> Function()>((ref) {
  final registrar = ref.read(pushRegistrarProvider);
  final social = ref.read(socialLoginRepositoryProvider);
  return () => signOut(registrar, Supabase.instance.client.auth, social: social);
});
