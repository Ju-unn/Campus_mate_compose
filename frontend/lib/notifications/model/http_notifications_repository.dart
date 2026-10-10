import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/notifications/model/app_notification.dart';
import 'package:campus_mate/notifications/model/notifications_repository.dart';

/// [NotificationsRepository] 를 FastAPI `/notifications*` 로 구현한다.
class HttpNotificationsRepository implements NotificationsRepository {
  const HttpNotificationsRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<NotificationsPage>> fetchPage({int limit = 30, String? before}) => _api.send(
        'GET',
        '/notifications',
        (body) {
          final json = body as Map<String, dynamic>;
          return NotificationsPage(
            items: [for (final raw in json['items'] as List<dynamic>) _parse(raw as Map<String, dynamic>)],
            unreadCount: json['unread_count'] as int,
            nextBefore: json['next_before'] as String?,
          );
        },
        query: {'limit': '$limit', 'before': ?before},
      );

  @override
  Future<Result<int>> fetchUnreadCount() =>
      _api.send('GET', '/notifications/unread-count', (body) => (body as Map<String, dynamic>)['unread_count'] as int);

  @override
  Future<Result<void>> markRead(String id) => _api.send<void>('POST', '/notifications/$id/read', (_) {});

  @override
  Future<Result<void>> markAllRead() => _api.send<void>('POST', '/notifications/read-all', (_) {});

  static AppNotification _parse(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as String,
        kind: NotificationKind.fromWire(json['kind']),
        title: json['title'] as String,
        body: json['body'] as String,
        data: (json['data'] as Map<String, dynamic>?) ?? const {},
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        read: json['read'] as bool,
      );
}
