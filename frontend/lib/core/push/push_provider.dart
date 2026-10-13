import 'package:campus_mate/core/push/foreground_push.dart';
import 'package:campus_mate/core/push/push_messaging.dart';
import 'package:campus_mate/core/push/push_registrar.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 실제 FCM. 테스트는 이 provider 를 가짜로 덮어써 Firebase 를 켜지 않는다.
final pushMessagingProvider = Provider<PushMessaging>((ref) {
  return FirebasePushMessaging(FirebaseMessaging.instance);
});

final pushRegistrarProvider = Provider<PushRegistrar>((ref) {
  return PushRegistrar(ref.read(pushMessagingProvider), ref.read(cardRepositoryProvider));
});

/// 기기 설정의 앱 알림 허용(16d-1). 화면이 다시 보일 때 invalidate 해서 새로 읽는다.
final deviceNotificationsPermittedProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.read(pushMessagingProvider).isPermitted(),
);

/// 안드로이드 시스템 알림 창구. 진짜(`local_system_notifications.dart`)는 main() 이 앱을 켤 때 한 번 만들어 덮어쓴다 —
/// 로그아웃하면 SessionScope 가 provider 를 새로 만드는데, 그때도 같은 것을 써야 "켠 알림은 한 번만 연다" 가 지켜진다.
/// 기본값은 아무것도 띄우지 않는다 — 시험이 플랫폼 채널 없이 앱을 띄운다(draftStoreProvider 와 같은 방식).
final systemNotificationsProvider = Provider<SystemNotifications>((ref) => const NoSystemNotifications());

/// 앱이 떠 있을 때 받은 푸시를 시스템 알림으로 보여 준다. 안드로이드만 직접 띄우고 iOS 는 FCM 표시 옵션을 켠다.
final foregroundPushProvider = Provider<ForegroundPush>((ref) {
  return ForegroundPush(
    ref.read(systemNotificationsProvider),
    ref.read(pushMessagingProvider),
    platform: defaultTargetPlatform,
  );
});
