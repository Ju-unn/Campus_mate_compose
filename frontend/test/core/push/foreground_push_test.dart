import 'package:campus_mate/core/push/foreground_push.dart';
import 'package:campus_mate/core/push/push_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_push_messaging.dart';
import 'fake_system_notifications.dart';

PushMessage _message(Map<String, dynamic> data, {String? title = '제목', String? body = '본문'}) =>
    (data: data, title: title, body: body);

void main() {
  late FakeSystemNotifications notifications;
  late FakePushMessaging messaging;

  ForegroundPush foregroundOn(TargetPlatform platform) {
    notifications = FakeSystemNotifications(launch: {'route': 'chat', 'match_id': 'm1'});
    messaging = FakePushMessaging(token: 't');
    return ForegroundPush(notifications, messaging, platform: platform);
  }

  group('start', () {
    test('안드로이드는 시스템 알림 창구를 준비하고, 그 알림으로 켠 앱이면 그 data 를 돌려준다', () async {
      final foreground = foregroundOn(TargetPlatform.android);

      expect(await foreground.start(), {'route': 'chat', 'match_id': 'm1'});
      expect(notifications.initializeCalls, 1);
      expect(messaging.presentWhileOpenCalls, 0);
    });

    // iOS 는 FCM 표시 옵션이 배너를 띄운다. 로컬 알림 창구를 켜면 iOS 권한 창 · 두 번 뜨는 알림 위험만 생긴다.
    test('iOS 는 FCM 포그라운드 표시를 켜고 시스템 알림 창구는 건드리지 않는다', () async {
      final foreground = foregroundOn(TargetPlatform.iOS);

      expect(await foreground.start(), isNull);
      expect(messaging.presentWhileOpenCalls, 1);
      expect(notifications.initializeCalls, 0);
    });
  });

  group('present', () {
    test('안드로이드는 앱이 떠 있을 때 받은 알림을 제목 · 본문 · data 그대로 시스템 알림으로 띄운다', () async {
      final foreground = foregroundOn(TargetPlatform.android);

      await foreground.present(
        _message({'route': 'acceptances', 'card_id': 'c1'}, title: '대화 신청이 왔어요', body: '새연결님이 신청했어요'),
        currentLocation: '/home',
      );

      expect(notifications.shown, hasLength(1));
      expect(notifications.shown.single.title, '대화 신청이 왔어요');
      expect(notifications.shown.single.body, '새연결님이 신청했어요');
      // 눌렀을 때 가는 곳은 이 data 의 route 로 정한다(PushRoute).
      expect(notifications.shown.single.data, {'route': 'acceptances', 'card_id': 'c1'});
    });

    test('iOS 는 시스템이 이미 띄우므로 따로 띄우지 않는다(같은 알림이 두 번 뜨지 않게)', () async {
      final foreground = foregroundOn(TargetPlatform.iOS);

      await foreground.present(_message({'route': 'daily_card'}), currentLocation: '/home');

      expect(notifications.shown, isEmpty);
    });

    // 그 방은 Realtime 으로 이미 보고 있다 — 알림까지 뜨면 같은 말을 두 번 듣는다.
    test('지금 열려 있는 그 방의 알림은 띄우지 않는다', () async {
      final foreground = foregroundOn(TargetPlatform.android);

      await foreground.present(_message({'route': 'chat', 'match_id': 'm1'}), currentLocation: '/chat/m1');

      expect(notifications.shown, isEmpty);
    });

    test('다른 방이 열려 있으면 띄운다', () async {
      final foreground = foregroundOn(TargetPlatform.android);

      await foreground.present(_message({'route': 'chat', 'match_id': 'm2'}), currentLocation: '/chat/m1');

      expect(notifications.shown, hasLength(1));
    });

    test('대화 탭 목록에 있어도 채팅 알림은 띄운다', () async {
      final foreground = foregroundOn(TargetPlatform.android);

      await foreground.present(_message({'route': 'chat', 'match_id': 'm1'}), currentLocation: '/conversations');

      expect(notifications.shown, hasLength(1));
    });

    test('제목이 없는 data 전용 알림은 띄우지 않는다', () async {
      final foreground = foregroundOn(TargetPlatform.android);

      await foreground.present(_message({'route': 'daily_card'}, title: null, body: null), currentLocation: '/home');

      expect(notifications.shown, isEmpty);
    });

    test('본문이 없으면 빈 본문으로 띄운다', () async {
      final foreground = foregroundOn(TargetPlatform.android);

      await foreground.present(_message({'route': 'daily_card'}, body: null), currentLocation: '/home');

      expect(notifications.shown.single.body, '');
    });

    // 같은 방 알림은 한 줄로 덮어쓰고(마지막 말만), 방이 다르거나 종류가 다르면 따로 쌓는다.
    test('같은 방 알림은 같은 id, 다른 방 · 다른 종류는 다른 id 로 띄운다', () async {
      final foreground = foregroundOn(TargetPlatform.android);
      for (final data in [
        {'route': 'chat', 'match_id': 'm1'},
        {'route': 'chat', 'match_id': 'm1'},
        {'route': 'chat', 'match_id': 'm2'},
        {'route': 'acceptances', 'card_id': 'c1'},
        {'route': 'match', 'match_id': 'm1'},
        {'route': 'friend_review_write', 'profile_id': 'p1'},
        {'route': 'friend_review_write', 'profile_id': 'p2'},
      ]) {
        await foreground.present(_message(data), currentLocation: '/home');
      }

      final ids = notifications.shown.map((shown) => shown.id).toList();
      expect(ids[0], ids[1]);
      expect(ids.skip(1).toSet(), hasLength(6));
      // 안드로이드 알림 id 는 32비트 정수다.
      expect(ids.every((id) => id >= 0 && id <= 0x7fffffff), isTrue);
    });
  });

  group('onTap', () {
    test('안드로이드는 시스템 알림 창구의 누름을 그대로 넘긴다', () async {
      final foreground = foregroundOn(TargetPlatform.android);
      final taps = <Map<String, dynamic>>[];
      final subscription = foreground.onTap.listen(taps.add);
      addTearDown(subscription.cancel);

      notifications.emitTap({'route': 'match', 'match_id': 'm1'});
      await Future<void>.delayed(Duration.zero);

      expect(taps, [
        {'route': 'match', 'match_id': 'm1'},
      ]);
    });

    test('iOS 는 누름이 FCM 으로 온다 — 여기서는 아무것도 넘기지 않는다', () async {
      final foreground = foregroundOn(TargetPlatform.iOS);

      expect(await foreground.onTap.isEmpty, isTrue);
    });
  });

  group('NoSystemNotifications', () {
    const none = NoSystemNotifications();

    test('준비해도 켠 알림이 없고, 띄워도 지워도 아무 일이 없고, 누름도 없다', () async {
      expect(await none.initialize(), isNull);
      await none.show(id: 1, title: '제목', body: '본문', data: const {});
      await none.cancel(id: 1, tag: 'verification_result');
      expect(await none.onTap.isEmpty, isTrue);
    });
  });
}
