import 'dart:async';

import 'package:campus_mate/chat/model/user_event.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
