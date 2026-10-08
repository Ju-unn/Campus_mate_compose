import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/auth/account_status_listenable.dart';

/// 로그아웃 뒤 시작 화면(스플래시를 고친 것, 예전에는 02 로그인 화면)에 한 번만 띄울 알림. **ProviderScope 밖** 정적 값이다.
///
/// 로그아웃하면 `SessionScope` 가 ProviderScope 를 통째로 새로 만들고(라우터 · ScaffoldMessenger 포함)
/// 스플래시도 다시 뜬다 — 로그아웃 전에 띄운 토스트는 함께 사라지고, provider 도 새로 시작해 값을 넘기지 못한다.
/// 그래서 로그아웃 직전에 여기 남기고, 시작 화면(`StartView`)이 [take] 로 꺼낸다(Ruling 36).
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

/// main.dart 가 계정 상태 리스너에서 부르는 한 줄. 탈퇴 · 로그인 만료일 때만 알림을 남기고 로그아웃한다.
/// 직접 탈퇴(16c)든 다른 기기에서 탈퇴한 계정(아무 API 401 + withdrawn)이든 이 길 하나다.
/// 로그인 만료(A11)도 같은 길로 시작 화면에 간다 — 그 화면이 알림을 띄운다.
void signOutWhenWithdrawn(AccountStatus status, Future<void> Function() signOut) {
  final notice = switch (status) {
    AccountStatus.withdrawn => const WithdrawnFailure(),
    AccountStatus.expired => const SessionRejectedFailure(),
    AccountStatus.active || AccountStatus.suspended => null,
  };
  if (notice == null) {
    return;
  }
  LoginNotice.post(notice.toDisplayMessage());
  unawaited(signOut());
}
