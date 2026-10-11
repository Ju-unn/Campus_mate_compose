import 'package:campus_mate/core/push/firebase_bootstrap.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('initializeFirebase', () {
    test('초기화가 되면 true 를 돌려준다', () async {
      expect(await initializeFirebase(init: () async {}), isTrue);
    });

    test('설정 파일이 없어 초기화가 실패해도 던지지 않고 false 를 돌려준다', () async {
      // iOS 에서 GoogleService-Info.plist 가 없으면 firebase_core 가 [core/not-initialized] 를 던진다.
      Future<void> failing() => throw FirebaseException(plugin: 'core', code: 'not-initialized');

      expect(await initializeFirebase(init: failing), isFalse);
    });
  });

  group('NoPushMessaging', () {
    const messaging = NoPushMessaging();

    test('알림 권한은 받지 못한 것으로 답하고 토큰은 없다', () async {
      expect(await messaging.requestPermission(), isFalse);
      expect(await messaging.isPermitted(), isFalse);
      expect(await messaging.getToken(), isNull);
    });

    test('받을 알림도 눌러 연 알림도 없다', () async {
      expect(await messaging.initialMessage(), isNull);
      expect(await messaging.onMessage.isEmpty, isTrue);
      expect(await messaging.onMessageOpenedApp.isEmpty, isTrue);
      expect(await messaging.onTokenRefresh.isEmpty, isTrue);
    });

    test('토큰 버리기와 설정 열기는 아무 일도 하지 않고 끝난다', () async {
      await messaging.deleteToken();
      await messaging.openNotificationSettings();
    });
  });
}
