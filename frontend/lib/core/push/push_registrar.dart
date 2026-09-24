import 'dart:async';

import 'package:campus_mate/core/push/push_messaging.dart';
import 'package:campus_mate/matching/model/card_repository.dart';

/// 토큰 등록·해제와 갱신 구독. 로그인한 뒤 [start], 로그아웃할 때 [stop].
///
/// [start] 는 여러 번 불러도 안전하다 — 새로 가입한 사용자는 학생 인증·학과 입력을
/// 마치기 전이라 서버가 등록을 403 으로 막는데, 그때는 토큰을 기억하지 않으므로
/// 인증 게이트가 열린 뒤 다시 부르면 그때 등록된다(2026-09-23 실기기 테스트).
class PushRegistrar {
  PushRegistrar(this._messaging, this._repository);

  final PushMessaging _messaging;
  final CardRepository _repository;

  StreamSubscription<String>? _refreshSubscription;
  String? _registeredToken;
  Future<void>? _starting;

  /// 겹쳐 불리면 진행 중인 시도를 같이 기다린다 — 로그인 직후와 게이트가 열리는 순간이
  /// 붙어 있으면 두 번째 호출이 첫 번째의 등록이 끝나기 전에 같은 토큰을 또 보낸다.
  Future<void> start() {
    if (_registeredToken != null) {
      return Future<void>.value();
    }
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<void> _start() async {
    if (!await _messaging.requestPermission()) {
      // 거부해도 앱은 그대로 쓴다. 알림 설정 화면(16d)에서 다시 켤 수 있다.
      return;
    }
    final token = await _messaging.getToken();
    if (token != null) {
      await _register(token);
    }
    _refreshSubscription ??= _messaging.onTokenRefresh.listen(_register);
  }

  Future<void> _register(String token) async {
    final result = await _repository.registerPushToken(token);
    // 서버가 받아 준 토큰만 기억한다 — 실패한 것을 기억하면 다시 시도하지 않고,
    // [stop] 이 서버에 없는 토큰을 지우려 한다.
    result.when(
      onSuccess: (_) {
        _registeredToken = token;
      },
      onFailure: (_) {},
    );
  }

  /// 로그아웃. 토큰을 남겨 두면 다음에 로그인한 사람에게 내 알림이 간다.
  Future<void> stop() async {
    await _refreshSubscription?.cancel();
    _refreshSubscription = null;
    final token = _registeredToken;
    _registeredToken = null;
    if (token != null) {
      await _repository.deletePushToken(token);
    }
  }
}
