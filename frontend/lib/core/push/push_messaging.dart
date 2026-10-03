import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

/// `FirebaseMessaging` 을 감싼 얇은 인터페이스. 테스트가 Firebase 를 켜지 않아도 되게 한다
/// (조각 1b 의 `FaceDetector` 래퍼와 같은 이유).
abstract interface class PushMessaging {
  Future<bool> requestPermission();

  /// 기기 설정에서 이 앱 알림을 허용했는지(16d-1). 묻지 않고 읽기만 한다.
  Future<bool> isPermitted();

  /// 기기의 이 앱 설정 화면을 연다. 거기서 "알림"을 눌러 켠다.
  Future<void> openNotificationSettings();
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
  Future<bool> requestPermission() async => _allows(await _messaging.requestPermission());

  @override
  Future<bool> isPermitted() async => _allows(await _messaging.getNotificationSettings());

  static bool _allows(NotificationSettings settings) =>
      settings.authorizationStatus == AuthorizationStatus.authorized ||
      settings.authorizationStatus == AuthorizationStatus.provisional;

  /// 알림 설정 화면에 바로 가는 길은 패키지 · 네이티브 코드가 더 든다 — 연락처 8a-2 와 같은 앱 설정 화면을 연다(대장 10-03 가).
  @override
  Future<void> openNotificationSettings() => FlutterContacts.permissions.openSettings();

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
