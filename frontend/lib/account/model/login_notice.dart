import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/auth/account_status_listenable.dart';

/// 로그인 화면(02)에 한 번만 띄울 알림. **ProviderScope 밖** 정적 값이다.
///
/// 로그아웃하면 `SessionScope` 가 ProviderScope 를 통째로 새로 만들고(라우터 · ScaffoldMessenger 포함)
/// 스플래시도 다시 뜬다 — 로그아웃 전에 띄운 토스트는 함께 사라지고, provider 도 새로 시작해 값을 넘기지 못한다.
/// 그래서 로그아웃 직전에 여기 남기고, 로그인 화면이 [take] 로 꺼낸다(Ruling 36).
abstract final class LoginNotice {
  static String? _message;

  static void post(String message) => _message = message;

  /// 한 번만 값을 주고 비운다 — 로그인 화면에 다시 들어와도 또 뜨지 않는다.
  static String? take() {
    final message = _message;
    _message = null;
    return message;
  }
}

/// main.dart 가 계정 상태 리스너에서 부르는 한 줄. 탈퇴일 때만 알림을 남기고 로그아웃한다.
/// 직접 탈퇴(16c)든 다른 기기에서 탈퇴한 계정(아무 API 401 + withdrawn)이든 이 길 하나다.
void signOutWhenWithdrawn(AccountStatus status, Future<void> Function() signOut) {
  if (status != AccountStatus.withdrawn) {
    return;
  }
  LoginNotice.post(const WithdrawnFailure().toDisplayMessage());
  unawaited(signOut());
}
