/// 알림 종류. 서버 `notifications.kind`(text + CHECK 6종, 설계 §9)를 그대로 받고,
/// 모르는 값은 [other] 로 읽어 화면이 죽지 않게 한다(서버가 종류를 늘려도 옛 앱은 종 그림으로 보인다).
enum NotificationKind {
  cardArrived('card_arrived'),
  chatRequest('chat_request'),
  matchMade('match_made'),
  friendReview('friend_review'),
  verificationResult('verification_result'),
  nightDigest('night_digest'),
  other('');

  const NotificationKind(this.wire);

  final String wire;

  static NotificationKind fromWire(Object? value) =>
      values.firstWhere((kind) => kind.wire == value && kind != other, orElse: () => other);
}

/// 알림함 한 줄(서버 `GET /notifications` 의 items 한 칸).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.data,
    required this.createdAt,
    required this.read,
  });

  final String id;
  final NotificationKind kind;
  final String title;
  final String body;

  /// 푸시 `data` 와 같은 값 — `route` 가 눌렀을 때 갈 화면이다(`PushRoute.resolve`).
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final bool read;

  AppNotification asRead() => AppNotification(
        id: id,
        kind: kind,
        title: title,
        body: body,
        data: data,
        createdAt: createdAt,
        read: true,
      );
}

/// 한 쪽 분량. [nextBefore] 가 null 이면 더 읽을 쪽이 없다.
class NotificationsPage {
  const NotificationsPage({required this.items, required this.unreadCount, this.nextBefore});

  final List<AppNotification> items;

  /// 목록 전체(읽어 온 쪽만이 아니라) 안 읽은 수.
  final int unreadCount;

  /// 서버가 준 값을 그대로 다음 요청 `before` 에 돌려준다(시간대 표기를 앱이 다시 만들지 않는다).
  final String? nextBefore;
}
