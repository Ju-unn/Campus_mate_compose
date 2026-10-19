import 'dart:async';
import 'dart:convert';

import 'package:campus_mate/core/push/foreground_push.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 안드로이드 시스템 알림 창구 — flutter_local_notifications 를 감싼다. iOS 에서는 쓰지 않는다([ForegroundPush]).
/// 앱을 켤 때 main() 이 한 번 만든다 — 로그아웃해도 새로 만들지 않아야 "켠 알림은 한 번만 연다" 가 지켜진다.
///
/// 권한은 묻지 않는다: 안드로이드 13+ 알림 권한(POST_NOTIFICATIONS)은 FCM 권한 요청([PushRegistrar])이 이미 묻는다.
class LocalSystemNotifications implements SystemNotifications {
  LocalSystemNotifications(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;
  final StreamController<Map<String, dynamic>> _taps = StreamController<Map<String, dynamic>>.broadcast();
  bool _initialized = false;

  /// 흰색 + 투명 실루엣(res/drawable-*/ic_stat_campusmate.png). FCM 기본 알림 아이콘과 같은 그림이다(AndroidManifest.xml).
  static const String _smallIcon = 'ic_stat_campusmate';

  /// MainActivity.kt 가 앱을 켤 때 만드는 채널과 id · 이름 · 설명이 같아야 한다 — 이미 있으면 플러그인은 그대로 쓴다.
  static final NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'campus_mate_default',
      'CampusMate 알림',
      channelDescription: '카드 도착 · 수락 · 매칭 · 채팅 알림',
      // 화면 위에 잠깐 내려오는 헤드업 알림이 되게 한다(안드로이드 7 이하는 priority, 8+ 는 채널 중요도).
      importance: Importance.high,
      priority: Priority.high,
      // 작은 아이콘(흰 실루엣) 뒤 원 색. AndroidManifest 의 default_notification_color 와 같은 대표 색이다.
      color: AppColors.primary,
    ),
  );

  /// 로그아웃 뒤 다시 로그인하면 또 불린다 — 그때는 켠 알림을 다시 돌려주지 않는다(다음 사람이 앞 사람 방을 열지 않게).
  @override
  Future<Map<String, dynamic>?> initialize() async {
    if (_initialized) {
      return null;
    }
    _initialized = true;
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings(_smallIcon)),
      onDidReceiveNotificationResponse: (response) => _forwardTap(response.payload),
    );
    return _launchData(await _plugin.getNotificationAppLaunchDetails());
  }

  static Map<String, dynamic>? _launchData(NotificationAppLaunchDetails? launch) =>
      launch?.didNotificationLaunchApp == true ? _decode(launch?.notificationResponse?.payload) : null;

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) =>
      _plugin.show(id: id, title: title, body: body, notificationDetails: _details, payload: jsonEncode(data));

  /// [initialize] 전에 불러도 된다 — 안드로이드 쪽은 엔진에 붙을 때 받은 context 로 지운다.
  @override
  Future<void> cancel({required int id, String? tag}) => _plugin.cancel(id: id, tag: tag);

  @override
  Stream<Map<String, dynamic>> get onTap => _taps.stream;

  void _forwardTap(String? payload) {
    final data = _decode(payload);
    if (data != null) {
      _taps.add(data);
    }
  }

  /// payload 는 [show] 가 넣은 data 의 JSON 이다. 비었거나 모양이 다르면 아무 데도 보내지 않는다(PushRoute 와 같은 원칙).
  static Map<String, dynamic>? _decode(String? payload) {
    try {
      final decoded = jsonDecode(payload ?? '');
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
