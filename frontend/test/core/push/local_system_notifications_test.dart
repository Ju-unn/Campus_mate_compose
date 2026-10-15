import 'dart:convert';

import 'package:campus_mate/core/push/local_system_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

/// flutter_local_notifications 의 안드로이드 채널을 가짜로 받아, 진짜 창구가 플러그인에 무엇을 넘기는지 본다.
/// (시험 기본 플랫폼은 안드로이드다.)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  Map<String, Object?>? launchDetails;

  setUp(() {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls = [];
    launchDetails = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'initialize' => true,
        'getNotificationAppLaunchDetails' => launchDetails,
        _ => null,
      };
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  LocalSystemNotifications create() => LocalSystemNotifications(FlutterLocalNotificationsPlugin());

  List<MethodCall> callsNamed(String method) => calls.where((call) => call.method == method).toList();

  test('알림 줄 작은 아이콘은 흰 실루엣 ic_stat_campusmate 로 준비한다', () async {
    await create().initialize();

    expect((callsNamed('initialize').single.arguments as Map)['defaultIcon'], 'ic_stat_campusmate');
  });

  test('그냥 켠 앱이면 켠 알림이 없다', () async {
    launchDetails = {'notificationLaunchedApp': false};

    expect(await create().initialize(), isNull);
  });

  // 앱이 떠 있을 때 띄운 알림이 줄에 남은 채 앱이 꺼졌다가, 그 알림을 눌러 다시 켠 경우.
  test('그 알림을 눌러 켠 앱이면 그 data 를 돌려주고, 로그아웃 뒤 다시 준비해도 또 돌려주지 않는다', () async {
    launchDetails = {
      'notificationLaunchedApp': true,
      'notificationResponse': {
        'notificationId': 7,
        'payload': jsonEncode({'route': 'chat', 'match_id': 'm1'}),
        'notificationResponseType': 0,
      },
    };
    final notifications = create();

    expect(await notifications.initialize(), {'route': 'chat', 'match_id': 'm1'});
    // 같은 앱에서 다음 사람이 로그인해도 앞 사람이 누른 알림의 방을 열지 않는다(main.dart _forgetSession 과 같은 이유).
    expect(await notifications.initialize(), isNull);
  });

  test('기존 채널 campus_mate_default 에 헤드업 중요도로, data 를 payload 에 실어 띄운다', () async {
    final notifications = create();
    await notifications.initialize();

    await notifications.show(id: 42, title: '새연결', body: '안녕하세요', data: {'route': 'chat', 'match_id': 'm1'});

    final arguments = callsNamed('show').single.arguments as Map;
    expect(arguments['id'], 42);
    expect(arguments['title'], '새연결');
    expect(arguments['body'], '안녕하세요');
    expect(jsonDecode(arguments['payload'] as String), {'route': 'chat', 'match_id': 'm1'});
    final android = arguments['platformSpecifics'] as Map;
    // MainActivity.kt 가 만든 채널과 같은 id · 이름이어야 한다 — 다르면 채널이 하나 더 생긴다.
    expect(android['channelId'], 'campus_mate_default');
    expect(android['channelName'], 'CampusMate 알림');
    expect(android['importance'], Importance.high.value);
    expect(android['priority'], Priority.high.value);
  });

  // FCM 이 띄운 알림은 id 가 늘 0 이고 tag 로만 가려진다. 관문 갱신이 준비보다 먼저 와도 지워져야 한다(준비 없이 부른다).
  test('지울 때 id 와 tag 를 플러그인에 그대로 넘긴다', () async {
    await create().cancel(id: 0, tag: 'verification_result');

    expect(callsNamed('cancel').single.arguments, {'id': 0, 'tag': 'verification_result'});
  });

  test('앱이 살아 있을 때 알림을 누르면 payload 의 data 를 넘긴다', () async {
    final notifications = create();
    await notifications.initialize();
    final taps = <Map<String, dynamic>>[];
    final subscription = notifications.onTap.listen(taps.add);
    addTearDown(subscription.cancel);

    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall('didReceiveNotificationResponse', {
        'notificationId': 42,
        'payload': jsonEncode({'route': 'match', 'match_id': 'm1'}),
        'notificationResponseType': 0,
      })),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);

    expect(taps, [
      {'route': 'match', 'match_id': 'm1'},
    ]);
  });

  test('payload 가 비었거나 깨졌으면 누름을 넘기지 않는다', () async {
    final notifications = create();
    await notifications.initialize();
    final taps = <Map<String, dynamic>>[];
    final subscription = notifications.onTap.listen(taps.add);
    addTearDown(subscription.cancel);

    for (final payload in ['', 'not-json', '[1]']) {
      await messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall('didReceiveNotificationResponse', {
          'notificationId': 42,
          'payload': payload,
          'notificationResponseType': 0,
        })),
        (_) {},
      );
    }
    await Future<void>.delayed(Duration.zero);

    expect(taps, isEmpty);
  });
}
