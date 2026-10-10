import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/notifications/model/app_notification.dart';

/// 09c 알림함과 홈 종 배지가 쓰는 서버 호출. 화면은 이 인터페이스만 보고 구현을 모른다.
abstract interface class NotificationsRepository {
  /// 최신순 한 쪽. [before] 는 앞 쪽의 `next_before` 를 그대로 넘긴다.
  Future<Result<NotificationsPage>> fetchPage({int limit = 30, String? before});

  /// 종 배지용 안 읽은 수.
  Future<Result<int>> fetchUnreadCount();

  /// 한 줄을 읽음으로(남의 것·없는 것은 404, 이미 읽은 것은 200 — 서버가 멱등).
  Future<Result<void>> markRead(String id);

  Future<Result<void>> markAllRead();
}
