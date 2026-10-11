import 'package:campus_mate/core/push/push_messaging.dart';
import 'package:firebase_core/firebase_core.dart';

/// `main()` 에서 한 번 부른다. 안드로이드는 google-services 플러그인이, iOS 는 `GoogleService-Info.plist` 가 설정을 준다.
/// 그 파일이 없는 빌드(CI · 아직 plist 를 못 넣은 iOS)는 `Firebase.initializeApp()` 이 던지는데,
/// 그 예외로 앱이 시작 화면조차 못 띄우면 안 된다 — false 를 돌려주고, 부른 쪽이 푸시 없이 계속 띄운다.
Future<bool> initializeFirebase({Future<void> Function()? init}) async {
  try {
    await (init ?? _initializeApp)();
    return true;
  } on Exception {
    return false;
  }
}

Future<void> _initializeApp() => Firebase.initializeApp();

/// Firebase 를 켜지 못한 빌드가 쓰는 대역. 권한은 없고 토큰도 알림도 없다 —
/// 그래서 [PushRegistrar] 는 권한 단계에서 조용히 멈추고, 알림 설정 화면은 "기기 알림 꺼짐" 으로 보인다.
class NoPushMessaging implements PushMessaging {
  const NoPushMessaging();

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<bool> isPermitted() async => false;

  @override
  Future<void> openNotificationSettings() async {}

  @override
  Future<String?> getToken() async => null;

  @override
  Future<void> deleteToken() async {}

  @override
  Stream<String> get onTokenRefresh => const Stream<String>.empty();

  @override
  Stream<Map<String, dynamic>> get onMessage => const Stream<Map<String, dynamic>>.empty();

  @override
  Stream<Map<String, dynamic>> get onMessageOpenedApp => const Stream<Map<String, dynamic>>.empty();

  @override
  Future<Map<String, dynamic>?> initialMessage() async => null;
}
