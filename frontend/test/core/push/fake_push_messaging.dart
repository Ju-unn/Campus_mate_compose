import 'dart:async';

import 'package:campus_mate/core/push/push_messaging.dart';

/// 테스트가 Firebase 를 켜지 않고도 토큰·알림 흐름을 돌려 보게 하는 가짜 구현.
class FakePushMessaging implements PushMessaging {
  FakePushMessaging({required this.token, this.granted = true});

  final String token;
  final bool granted;
  final StreamController<String> _refresh = StreamController<String>.broadcast();

  void emitRefreshedToken(String value) => _refresh.add(value);

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<String?> getToken() async => token;

  @override
  Stream<String> get onTokenRefresh => _refresh.stream;

  @override
  Stream<Map<String, dynamic>> get onMessage => const Stream.empty();

  @override
  Stream<Map<String, dynamic>> get onMessageOpenedApp => const Stream.empty();

  @override
  Future<Map<String, dynamic>?> initialMessage() async => null;
}
