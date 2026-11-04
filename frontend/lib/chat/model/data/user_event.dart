import 'package:campus_mate/chat/model/data/message.dart';

/// 서버가 쓰기 직후 내 비공개 채널 `user:<내 profile_id>` 로 쏘는 이벤트(채팅 실시간 전환 설계안 A, 서버 PR #508).
/// **빨리 보여 주는 용도다** — 값의 기준은 늘 서버 API 이고, 유실돼도 폴링 · 복귀 새로고침이 메운다.
sealed class UserEvent {
  const UserEvent(this.matchId);

  final String matchId;

  /// 서버가 쓰는 Broadcast 이벤트 이름들. 채널은 이 이름마다 한 번씩 귀를 연다.
  static const List<String> names = ['message', 'read', 'room_changed'];

  /// Dart `onBroadcast` 콜백이 주는 맵 **전체**(`{type, event, payload}`)를 읽는다 — 우리 값은 그 안의 `payload` 다.
  /// 모르는 이벤트 · 모르는 메시지 종류 · 모양이 이상한 값은 던지지 않고 null 이다(받는 쪽이 그 한 건만 버린다).
  static UserEvent? fromBroadcast(Map<String, dynamic> broadcast) {
    final payload = broadcast['payload'];
    if (payload is! Map || payload['match_id'] is! String) {
      return null;
    }
    try {
      return _parse(broadcast['event'], Map<String, dynamic>.from(payload));
    } on TypeError {
      return null;
    } on FormatException {
      return null;
    }
  }

  static UserEvent? _parse(Object? event, Map<String, dynamic> payload) {
    final matchId = payload['match_id'] as String;
    return switch (event) {
      'message' => MessageEvent._parse(matchId, payload),
      'read' => ReadEvent._parse(matchId, payload),
      'room_changed' => RoomChangedEvent(matchId),
      _ => null,
    };
  }
}

/// 방에 남은 두 사람이 받는다(보낸 사람 본인도 — 다른 기기 목록용). 나가기 · 차단 줄도 kind=left 인 이것으로 온다.
final class MessageEvent extends UserEvent {
  const MessageEvent(super.matchId, this.message);

  final Message message;

  static MessageEvent? _parse(String matchId, Map<String, dynamic> payload) {
    final message = Message.fromJson(Map<String, dynamic>.from(payload['message'] as Map));
    return message == null ? null : MessageEvent(matchId, message);
  }
}

/// 상대가 방을 읽었다 — 상대 한 명에게만 온다. 시각은 오프셋이 다를 수 있어(+09:00 · +00:00) 순간으로 읽는다.
final class ReadEvent extends UserEvent {
  const ReadEvent(super.matchId, {required this.readerId, required this.readAt});

  final String readerId;
  final DateTime readAt;

  static ReadEvent _parse(String matchId, Map<String, dynamic> payload) => ReadEvent(
        matchId,
        readerId: payload['reader_id'] as String,
        readAt: DateTime.parse(payload['last_read_at'] as String).toLocal(),
      );
}

/// 새 매칭 · 방 닫힘. 새 방은 상대 프로필이 있어야 그릴 수 있어 신호만 온다 — 받으면 목록을 다시 읽는다.
final class RoomChangedEvent extends UserEvent {
  const RoomChangedEvent(super.matchId);
}
