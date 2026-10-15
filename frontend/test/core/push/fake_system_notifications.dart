import 'dart:async';

import 'package:campus_mate/core/push/foreground_push.dart';

/// 띄운 시스템 알림 한 건 — 시험이 무엇을 띄웠는지 본다.
typedef ShownNotification = ({int id, String title, String body, Map<String, dynamic> data});

/// 플랫폼 채널 없이 시스템 알림 창구를 흉내 낸다.
class FakeSystemNotifications implements SystemNotifications {
  FakeSystemNotifications({this.launch});

  /// 꺼진 앱을 이 창구가 띄운 알림을 눌러 켰다고 흉내 낸다. null 이면 그냥 켠 것이다.
  final Map<String, dynamic>? launch;
  int initializeCalls = 0;
  final List<ShownNotification> shown = [];

  /// 지운 알림 — FCM 이 띄운 알림은 tag 로, 앱이 띄운 알림은 id 로 지운다.
  final List<({int id, String? tag})> cancelled = [];
  final StreamController<Map<String, dynamic>> _taps = StreamController<Map<String, dynamic>>.broadcast();

  /// 앱이 살아 있을 때 이 창구가 띄운 알림을 눌렀다고 흉내 낸다.
  void emitTap(Map<String, dynamic> data) => _taps.add(data);

  @override
  Future<Map<String, dynamic>?> initialize() async {
    initializeCalls++;
    return launch;
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async =>
      shown.add((id: id, title: title, body: body, data: data));

  @override
  Future<void> cancel({required int id, String? tag}) async => cancelled.add((id: id, tag: tag));

  @override
  Stream<Map<String, dynamic>> get onTap => _taps.stream;
}
