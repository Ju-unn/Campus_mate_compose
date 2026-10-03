import 'dart:async';

import 'package:campus_mate/core/push/push_messaging.dart';

/// 테스트가 Firebase 를 켜지 않고도 토큰·알림 흐름을 돌려 보게 하는 가짜 구현.
class FakePushMessaging implements PushMessaging {
  FakePushMessaging({required this.token, this.granted = true, this.initial});

  final String token;
  final bool granted;

  /// 기기 설정의 앱 알림 허용(16d-1). 테스트가 "설정에서 켜고 돌아옴"을 흉내 내려고 바꾼다.
  bool permitted = true;

  /// 주면 기기 설정 읽기가 이 Future 를 기다린다 — "읽는 중" 을 흉내 낸다.
  Future<bool>? permittedPending;
  int openedSettings = 0;

  /// 꺼진 앱을 이 알림을 눌러 켰다고 흉내 낸다. null 이면 그냥 켠 것이다.
  final Map<String, dynamic>? initial;

  /// 기기에서 토큰 버리기([deleteToken])가 몇 번 더 실패할지(인터넷 없음 흉내). 부를 때마다 하나씩 준다.
  int deleteTokenFailures = 0;
  int deleteTokenCalls = 0;
  int deletedOnDevice = 0;

  /// 있으면 [deleteToken] 이 이것이 끝날 때까지 기다린다(느린 망 흉내).
  Completer<void>? deleteTokenGate;

  /// [getToken] 을 부른 순간의 [deletedOnDevice] — 버리기가 끝난 뒤에 토큰을 받았는지 본다.
  final List<int> getTokenAfterDeletes = [];
  final StreamController<String> _refresh = StreamController<String>.broadcast();

  void emitRefreshedToken(String value) => _refresh.add(value);

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<bool> isPermitted() async => permittedPending ?? permitted;

  @override
  Future<void> openNotificationSettings() async => openedSettings++;

  @override
  Future<String?> getToken() async {
    getTokenAfterDeletes.add(deletedOnDevice);
    return token;
  }

  @override
  Future<void> deleteToken() async {
    deleteTokenCalls++;
    final gate = deleteTokenGate;
    if (gate != null) {
      await gate.future;
    }
    if (deleteTokenFailures > 0) {
      deleteTokenFailures--;
      throw Exception('SERVICE_NOT_AVAILABLE');
    }
    deletedOnDevice++;
  }

  @override
  Stream<String> get onTokenRefresh => _refresh.stream;

  @override
  Stream<Map<String, dynamic>> get onMessage => const Stream.empty();

  @override
  Stream<Map<String, dynamic>> get onMessageOpenedApp => const Stream.empty();

  @override
  Future<Map<String, dynamic>?> initialMessage() async => initial;
}
