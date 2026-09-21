import 'dart:async';

import 'package:campus_mate/core/push/push_messaging.dart';
import 'package:campus_mate/matching/model/card_repository.dart';

/// 토큰 등록·해제와 갱신 구독. 앱이 켜질 때 한 번 [start], 로그아웃할 때 [stop].
class PushRegistrar {
  PushRegistrar(this._messaging, this._repository);

  final PushMessaging _messaging;
  final CardRepository _repository;

  StreamSubscription<String>? _refreshSubscription;
  String? _registeredToken;

  Future<void> start() async {
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
    _registeredToken = token;
    await _repository.registerPushToken(token);
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
