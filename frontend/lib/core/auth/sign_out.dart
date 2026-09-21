import 'package:campus_mate/core/push/push_registrar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 로그아웃은 반드시 여기를 지난다.
///
/// `signOut()` 을 먼저 부르면 세션이 사라진 뒤에야 [PushRegistrar.stop] 이 불린다.
/// 그 안의 `DELETE /cards/push-tokens/{token}` 은 실어 보낼 토큰이 없어 401 로 끝나고,
/// 이 기기의 FCM 토큰은 서버에 그대로 남는다 — 다음으로 로그인한 사람이 덮어쓸 때까지
/// 죽은 토큰이 쌓인다. 그래서 지우고 나서 나간다.
Future<void> signOut(PushRegistrar registrar, GoTrueClient auth) async {
  await registrar.stop();
  await auth.signOut();
}
