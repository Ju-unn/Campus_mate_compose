import 'package:campus_mate/core/push/push_messaging.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockFirebaseMessaging extends Mock implements FirebaseMessaging {}

void main() {
  group('pushMessageOf', () {
    // 앱이 떠 있을 때 받은 알림을 시스템 알림으로 다시 띄우려면 제목 · 본문이 있어야 한다 — 예전에는 data 만 넘겨 버렸다.
    test('FCM 알림의 제목 · 본문 · data 를 함께 넘긴다', () {
      const remote = RemoteMessage(
        data: {'route': 'chat', 'match_id': 'm1'},
        notification: RemoteNotification(title: '새연결', body: '안녕하세요'),
      );

      final message = pushMessageOf(remote);

      expect(message.data, {'route': 'chat', 'match_id': 'm1'});
      expect(message.title, '새연결');
      expect(message.body, '안녕하세요');
    });

    test('notification 이 없는 data 전용 알림이면 제목 · 본문은 비어 있다', () {
      const remote = RemoteMessage(data: {'route': 'daily_card'});

      final message = pushMessageOf(remote);

      expect(message.data, {'route': 'daily_card'});
      expect(message.title, isNull);
      expect(message.body, isNull);
    });
  });

  group('FirebasePushMessaging.presentWhileOpen', () {
    // iOS 는 이 옵션이 켜져야 앱이 떠 있을 때도 시스템 배너가 뜬다(안드로이드에서는 FCM 이 아무 일도 하지 않는다).
    test('배너 · 배지 · 소리를 모두 켠다', () async {
      final firebase = _MockFirebaseMessaging();
      when(() => firebase.setForegroundNotificationPresentationOptions(
            alert: any(named: 'alert'),
            badge: any(named: 'badge'),
            sound: any(named: 'sound'),
          )).thenAnswer((_) async {});

      await FirebasePushMessaging(firebase).presentWhileOpen();

      verify(() => firebase.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true))
          .called(1);
    });
  });
}
