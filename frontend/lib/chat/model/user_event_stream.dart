import 'dart:async';

import 'package:campus_mate/chat/model/message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

/// 로그인한 사람의 우편함 채널. **Realtime 을 이 뒤에 숨긴다** — 시험은 가짜를 끼운다(방 채널 `MessageStream` 과 같은 경계).
abstract interface class UserEventStream {
  /// [profileId] 의 채널을 연다. 서버가 입장을 받아 주면(SUBSCRIBED) [onSubscribed] — 그때부터 이벤트가 온다.
  /// 입장 거부(정책 없음) · 끊김 · 타임아웃 · 서버가 닫음은 **스트림 오류**다. 다시 붙이기는 받는 쪽 몫이다 —
  /// 오류가 오면 이 구독을 끊고(채널도 닫힌다) 새로 구독한다.
  Stream<UserEvent> subscribe(String profileId, {void Function()? onSubscribed});
}

/// Supabase Realtime 구현. **private 채널이어야 한다** — public 으로 열면 같은 이름이라도 다른 채널이라 아무것도 안 온다.
/// 입장 권한은 `realtime.messages` 의 받기 정책(본인 토픽만)이 정한다. 토큰이 갱신되면 supabase 가 열린 채널에 새 토큰을 넣는다.
class RealtimeUserEventStream implements UserEventStream {
  const RealtimeUserEventStream(this._client);

  final SupabaseClient _client;

  @override
  Stream<UserEvent> subscribe(String profileId, {void Function()? onSubscribed}) {
    RealtimeChannel? channel;
    late final StreamController<UserEvent> controller;
    controller = StreamController<UserEvent>(
      onListen: () => channel = _open(profileId, controller, onSubscribed),
      onCancel: () async {
        final open = channel;
        channel = null;
        if (open != null) {
          await _client.removeChannel(open);
        }
      },
    );
    return controller.stream;
  }

  RealtimeChannel _open(String profileId, StreamController<UserEvent> controller, void Function()? onSubscribed) {
    var channel = _client.channel('user:$profileId', opts: const RealtimeChannelConfig(private: true));
    for (final name in UserEvent.names) {
      channel = channel.onBroadcast(event: name, callback: (broadcast) => _deliver(controller, broadcast));
    }
    return channel.subscribe(_statusListener(controller, onSubscribed));
  }

  static void _deliver(StreamController<UserEvent> controller, Map<String, dynamic> broadcast) {
    final event = UserEvent.fromBroadcast(broadcast);
    if (event != null && controller.hasListener) {
      controller.add(event);
    }
  }

  /// 붙음만 알리고 나머지는 모두 끊김이다. `closed` 도 끊김이다 — 서버가 닫으면(토큰 만료 등) 더는 이벤트가 안 오는데
  /// 연결됨으로 남으면 폴링이 느린 채로 굳는다. 우리가 지운 뒤 오는 `closed` 는 받는 쪽이 이미 끊어 버린다.
  static void Function(RealtimeSubscribeStatus, Object?) _statusListener(
    StreamController<UserEvent> controller,
    void Function()? onSubscribed,
  ) {
    return (status, error) {
      if (!controller.hasListener) {
        return;
      }
      if (status == RealtimeSubscribeStatus.subscribed) {
        onSubscribed?.call();
        return;
      }
      controller.addError(error ?? StateError('realtime ${status.name}'));
    };
  }
}
