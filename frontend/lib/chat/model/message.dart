/// 메시지의 종류(ERD `messages.kind`). `text` 가 아니면 말풍선이 아니라
/// 가운데 정렬 시스템 줄로 그린다(pen `CbXi6`).
enum MessageKind {
  text('text'),
  left('left'),
  trustAccept('trust_accept');

  const MessageKind(this.wire);

  final String wire;

  /// 모르는 값이면 null. 종류가 나중에 늘어도 옛 앱이 깨지지 않는 쪽을 택했다.
  static MessageKind? fromWire(String value) {
    for (final kind in values) {
      if (kind.wire == value) {
        return kind;
      }
    }
    return null;
  }
}

/// 메시지 한 통. 화면은 "내 것 / 상대 것 / 시스템" 과 시각만 쓴다(DESIGN §8.6).
class Message {
  const Message({
    required this.id,
    required this.senderId,
    required this.body,
    required this.kind,
    required this.createdAt,
  });

  final String id;
  final String senderId;

  /// 시스템 줄도 서버가 문장을 통째로 만들어 담아 준다 — 앱이 조립하지 않는다.
  final String body;
  final MessageKind kind;
  final DateTime createdAt;

  bool get isSystem => kind != MessageKind.text;

  /// **모르는 `kind` 면 null 을 돌려준다** — 부른 쪽이 그 줄만 건너뛴다.
  /// 파싱 실패 한 건으로 대화 전체가 안 보이면 그게 더 큰 사고다.
  static Message? fromJson(Map<String, dynamic> json) {
    final kind = MessageKind.fromWire(json['kind'] as String);
    if (kind == null) {
      return null;
    }
    return Message(
      id: json['id'] as String,
      senderId: json['sender_id'] as String,
      body: json['body'] as String,
      kind: kind,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }

  /// 목록 응답 한 덩어리에서 읽을 수 있는 줄만 추린다.
  static List<Message> listFromJson(List<dynamic> items) => items
      .map((item) => Message.fromJson(item as Map<String, dynamic>))
      .whereType<Message>()
      .toList();
}
