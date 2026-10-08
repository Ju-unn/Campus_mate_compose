import 'package:supabase_flutter/supabase_flutter.dart';

/// 학교 메일 인증 동안만 쓰는 임시 Supabase 연결 하나를 들고 있다.
///
/// 앱 시작이 아니라 처음 쓸 때 만들고([open]), 인증이 끝나면 이 기기에서만 로그아웃해 버린다([close]).
/// 메모리에만 있으므로 앱을 끄면 같이 사라진다 — 그것이 의도다(02 에서 다시 받는다).
class TemporaryAuthConnection {
  TemporaryAuthConnection(this._create);

  final GoTrueClient Function() _create;
  GoTrueClient? _client;

  /// 지금 연결. 없으면 새로 만든다. 02 에서 보낸 연결로 03 에서 확인해야 해서 닫기 전까지 같은 것을 준다.
  GoTrueClient open() => _client ??= _create();

  /// 메모리 세션을 비우고 연결을 버린다. 임시 이메일 계정은 서버가 지우므로 여기서는 지우지 않는다.
  /// gotrue 는 서버에 알리기 전에 메모리 세션부터 지운다 — 알림이 실패해도 비우기는 끝났으니 삼킨다.
  Future<void> close() async {
    final client = _client;
    _client = null;
    if (client == null) {
      return;
    }
    try {
      await client.signOut(scope: SignOutScope.local);
    } on Exception {
      // 위 주석 — 남은 것은 서버 쪽 알림뿐이다.
    } finally {
      client.dispose();
    }
  }
}
