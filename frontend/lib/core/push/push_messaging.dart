import 'package:firebase_messaging/firebase_messaging.dart';

/// `FirebaseMessaging` 을 감싼 얇은 인터페이스. 테스트가 Firebase 를 켜지 않아도 되게 한다
/// (조각 1b 의 `FaceDetector` 래퍼와 같은 이유).
abstract interface class PushMessaging {
  Future<bool> requestPermission();
  Future<String?> getToken();

  /// 이 기기의 토큰을 FCM 에서 버린다. 로그인이 필요 없다 — 버린 토큰으로 보내면 FCM 이 404 를 준다.
  /// 인터넷이 없으면 던진다.
  Future<void> deleteToken();
  Stream<String> get onTokenRefresh;
  Stream<Map<String, dynamic>> get onMessage;
  Stream<Map<String, dynamic>> get onMessageOpenedApp;
  Future<Map<String, dynamic>?> initialMessage();
}

class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging(this._messaging);

  final FirebaseMessaging _messaging;

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Future<void> deleteToken() => _messaging.deleteToken();

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Stream<Map<String, dynamic>> get onMessage =>
      FirebaseMessaging.onMessage.map((message) => message.data);

  @override
  Stream<Map<String, dynamic>> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp.map((message) => message.data);

  @override
  Future<Map<String, dynamic>?> initialMessage() async =>
      (await _messaging.getInitialMessage())?.data;
}
