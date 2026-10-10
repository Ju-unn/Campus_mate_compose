import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:campus_mate/notifications/model/http_notifications_repository.dart';
import 'package:campus_mate/notifications/model/notifications_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 알림함이 쓰는 저장소. 테스트는 이 provider 를 가짜로 덮어쓴다.
final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) {
  return HttpNotificationsRepository(ref.read(apiClientProvider));
});
