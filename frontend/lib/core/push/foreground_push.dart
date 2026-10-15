import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/core/push/push_messaging.dart';
import 'package:campus_mate/core/push/push_route.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:flutter/foundation.dart';

/// 시스템 알림 창구 — 알림 줄에 한 건 띄우고, 누르면 그 data 를 돌려준다.
/// 안드로이드 진짜는 flutter_local_notifications 를 감싼 `local_system_notifications.dart` 다.
/// 시험은 가짜로 바꿔 플랫폼 채널 없이 돈다(`PushMessaging` 과 같은 경계).
abstract interface class SystemNotifications {
  /// 한 번 준비한다. 꺼진 앱을 이 창구가 띄운 알림을 눌러 켰으면 그 알림의 data 를 돌려준다.
  Future<Map<String, dynamic>?> initialize();

  /// 같은 [id] 로 다시 띄우면 알림 줄의 앞 알림을 덮어쓴다.
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  });

  /// 알림 줄에서 지운다. FCM SDK 가 띄운 알림(앱이 뒤에 있을 때)은 [tag] 로 가려진다 — 이 앱이 띄운 알림은 tag 가 없다.
  Future<void> cancel({required int id, String? tag});

  /// 앱이 살아 있을 때 이 창구가 띄운 알림을 누르면 그 알림의 data 가 온다.
  Stream<Map<String, dynamic>> get onTap;
}

/// 진짜 창구를 넣지 않은 자리(시험 · main() 을 지나지 않는 앱)의 기본값. 아무것도 띄우지 않는다.
/// 진짜는 main() 이 한 번 만들어 덮어쓴다(`push_provider.dart` systemNotificationsProvider).
class NoSystemNotifications implements SystemNotifications {
  const NoSystemNotifications();

  @override
  Future<Map<String, dynamic>?> initialize() async => null;

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {}

  @override
  Future<void> cancel({required int id, String? tag}) async {}

  @override
  Stream<Map<String, dynamic>> get onTap => const Stream<Map<String, dynamic>>.empty();
}

/// 앱이 화면에 떠 있을 때 받은 푸시를 시스템 알림으로 보여 준다(2026-10-13 사용자 요청 — 조각 4 계획서의
/// "앱이 켜져 있으면 배너를 띄우지 않는다" 를 뒤집었다). 화면 목록 갱신 · 종 배지는 그대로 main.dart 가 한다.
/// - 안드로이드: FCM 은 앱이 앞에 있으면 알림을 띄우지 않는다 → 앱이 [SystemNotifications] 로 직접 띄운다.
/// - iOS: FCM 표시 옵션([PushMessaging.presentWhileOpen])을 켜면 시스템이 띄운다 → 여기서는 띄우지 않는다(두 번 뜨지 않게).
///   그래서 iOS 는 "지금 열려 있는 방" 알림도 막지 못한다 — 시스템이 앱에 묻지 않고 띄운다.
class ForegroundPush {
  ForegroundPush(this._notifications, this._messaging, {required TargetPlatform platform})
      : _drawsItself = platform == TargetPlatform.android;

  final SystemNotifications _notifications;
  final PushMessaging _messaging;

  /// 이 앱이 시스템 알림을 직접 그리는 플랫폼인가(안드로이드).
  final bool _drawsItself;

  /// 안드로이드 알림 id 는 32비트 양의 정수여야 한다.
  static const int _maxNotificationId = 0x7fffffff;

  /// 학생 인증 결과 알림(서버 kind `verification_result`)의 data. 이 앱이 띄울 때 id 를 이 data 로 정한다([_idFor]).
  static const Map<String, dynamic> _verificationResultData = {'route': 'verification'};

  /// 서버가 학생 인증 결과 알림에 붙이는 안드로이드 notification.tag(`backend/app/cards/push.py` _COLLAPSED_KINDS).
  static const String _verificationResultTag = 'verification_result';

  /// FCM SDK 가 띄운 알림의 id 는 늘 0 이다 — tag 로만 서로 갈린다.
  static const int _fcmNotificationId = 0;

  /// 학생 인증 관문을 이미 지났는가. 지나는 순간 한 번만 지우려고 앞 값을 기억한다([gateChanged]).
  bool _pastStudentVerification = false;

  /// 로그인 뒤 푸시를 켤 때 부른다. 안드로이드에서 꺼진 앱을 이 알림으로 켰으면 그 data 를 돌려준다.
  Future<Map<String, dynamic>?> start() async {
    if (!_drawsItself) {
      await _messaging.presentWhileOpen();
      return null;
    }
    return _notifications.initialize();
  }

  /// 앱이 직접 띄운 알림을 눌렀을 때. iOS 알림 누름은 FCM `onMessageOpenedApp` 으로 온다.
  Stream<Map<String, dynamic>> get onTap =>
      _drawsItself ? _notifications.onTap : const Stream<Map<String, dynamic>>.empty();

  /// [currentLocation] 은 지금 맨 위에 열린 화면의 경로다(push 로 연 채팅방 포함).
  Future<void> present(PushMessage message, {required String currentLocation}) async {
    final title = message.title;
    if (!_drawsItself || title == null || _isOpenRoom(message.data, currentLocation)) {
      return;
    }
    await _notifications.show(id: _idFor(message.data), title: title, body: message.body ?? '', data: message.data);
  }

  /// 관문이 바뀔 때마다 부른다. 학생 인증 관문을 지나는 순간(3c · 홈이 되는 순간) 학생 인증 결과 알림을 알림 줄에서 지운다 —
  /// 그 내용("학과 정보를 입력하고 시작해 보세요")은 화면이 이미 보여 준다. 앱이 뒤에 있을 때 FCM 이 띄운 것(tag)과
  /// 앞에 있을 때 앱이 띄운 것(id) 둘 다. 앱을 켜서 관문을 처음 알아낸 때(모름 → 홈)도 한 번 지운다 — 없으면 아무 일도 없다.
  /// iOS 는 로컬 알림 창구를 안드로이드 설정으로만 준비해 지우지 못한다 — 서버 `apns-collapse-id` 로 한 장으로 합치기만 한다.
  Future<void> gateChanged(VerificationGate gate) async {
    final past = gate == VerificationGate.needsSchoolInfo || gate == VerificationGate.complete;
    final justPassed = past && !_pastStudentVerification;
    _pastStudentVerification = past;
    if (!_drawsItself || !justPassed) {
      return;
    }
    await _notifications.cancel(id: _fcmNotificationId, tag: _verificationResultTag);
    await _notifications.cancel(id: _idFor(_verificationResultData));
  }

  /// 그 방은 Realtime 으로 이미 보고 있다. 채팅방만 본다 — 대화 목록 같은 다른 화면에서는 띄운다.
  static bool _isOpenRoom(Map<String, dynamic> data, String currentLocation) =>
      currentLocation.startsWith('${AppRoutes.chatRoom}/') && PushRoute.resolve(data) == currentLocation;

  /// 같은 방(match_id) · 같은 친구(profile_id) · 같은 종류(route)는 한 줄로 덮어쓰고, 나머지는 따로 쌓는다.
  /// ponytail: 문자열 해시라 서로 다른 열쇠가 우연히 같은 id 가 되면 앞 알림을 덮는다 — 그때 열쇠별 번호표로 바꾼다.
  static int _idFor(Map<String, dynamic> data) =>
      [data['route'], data['match_id'], data['profile_id']].join('|').hashCode & _maxNotificationId;
}
