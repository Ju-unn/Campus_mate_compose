import 'package:campus_mate/core/push/push_messaging.dart';
import 'package:campus_mate/core/push/push_registrar.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 실제 FCM. 테스트는 이 provider 를 가짜로 덮어써 Firebase 를 켜지 않는다.
final pushMessagingProvider = Provider<PushMessaging>((ref) {
  return FirebasePushMessaging(FirebaseMessaging.instance);
});

final pushRegistrarProvider = Provider<PushRegistrar>((ref) {
  return PushRegistrar(ref.read(pushMessagingProvider), ref.read(cardRepositoryProvider));
});
