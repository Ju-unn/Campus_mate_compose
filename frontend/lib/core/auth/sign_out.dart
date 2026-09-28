import 'package:campus_mate/core/push/push_provider.dart';
import 'package:campus_mate/core/push/push_registrar.dart';
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
Future<void> signOut(PushRegistrar registrar, GoTrueClient auth) async {
  await registrar.stop();
  try {
    await auth.signOut();
  } on AuthException {
    // 위 주석 — 남은 것은 서버 쪽 알림뿐이다.
  }
}

/// 설정 16g 가 부르는 로그아웃. 테스트는 덮어써 Supabase 를 켜지 않는다.
/// registrar 는 main.dart 가 [PushRegistrar.start] 한 그 인스턴스여야 등록한 토큰을 지운다 — 같은 provider 에서 읽는다.
final signOutProvider = Provider<Future<void> Function()>((ref) {
  final registrar = ref.read(pushRegistrarProvider);
  return () => signOut(registrar, Supabase.instance.client.auth);
});
