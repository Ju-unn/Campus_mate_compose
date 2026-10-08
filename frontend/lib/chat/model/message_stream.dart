import 'dart:async';

import 'package:campus_mate/chat/model/message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 방을 열고 있는 동안 새 메시지를 밀어 주는 통로.
/// **Realtime 을 이 뒤에 숨긴다** — 테스트는 가짜를 끼우고 Supabase 를 켜지 않는다
/// (조각 4 의 `PushMessaging` 과 같은 경계).
abstract interface class MessageStream {
  /// 구독을 끊으면 채널도 닫힌다. 목록 화면은 구독하지 않는다(푸시 + 당겨서 새로고침).
  ///
  /// 통로가 끊기면 **스트림 오류**가 온다 — 받는 쪽은 그때 배너를 띄우고 다시 구독한다(백로그 19).
  /// 끊겼던 통로가 스스로 다시 붙으면 [onRejoined] — 끊긴 동안 온 줄은 구독으로 안 오니 다시 읽어야 한다(결함 A12).
  /// 서버가 이 구독의 글을 **실제로 밀어 줄 준비가 됐을 수 있는** 때마다 [onReady] — 처음 붙었을 때와 postgres_changes
  /// 구독이 서버에 만들어졌다는 system 이벤트가 올 때(E-CHAT-67). 복제는 join 성공 뒤에 비동기로 살아서 그 전에 들어온 줄은
  /// 구독으로 안 오니, 받는 쪽은 한 번 더 읽는다. 여러 번 불릴 수 있으니 받는 쪽은 멱등이어야 한다.
  Stream<Message> subscribe(String matchId, {void Function()? onRejoined, void Function()? onReady});
}

/// Realtime 채널 상태를 받는 쪽 신호로 바꾼다. 끊김·타임아웃은 [onError]. `closed` 는 우리가
/// [SupabaseClient.removeChannel] 한 뒤에도 오는 값이라 올리지 않는다 — 받으면 화면을 닫을 때마다 "끊겼어요" 가 뜬다.
/// Realtime 은 끊기면 channelError 를 준 뒤 스스로 다시 붙어 `subscribed` 를 또 준다 — **끊김 뒤의** `subscribed` 만
/// [onRejoined]. 처음 붙기 전에 끊긴 것(타임아웃 · 소켓 연결 실패)도 그 사이 온 줄을 놓쳤으니 같다.
/// 끊김 없는 `subscribed` 에 부르면 다시 구독 → 다시 붙음이 끝없이 돈다.
/// 끊김 없는 `subscribed` 는 대신 [onReady] 다 — 복제는 join 응답 **뒤에** 비동기로 살아서 이 순간에도 아직 안 살았을 수 있지만,
/// 첫 페이지를 읽은 뒤 ~ 붙음 사이에 들어온 줄은 이제부터 놓칠 일이 없다(받는 쪽이 첫 페이지를 한 번 더 읽는다).
void Function(RealtimeSubscribeStatus, Object?) channelStatusListener({
  required void Function(Object error) onError,
  void Function()? onRejoined,
  void Function()? onReady,
}) {
  var dropped = false;
  return (status, error) {
    if (status == RealtimeSubscribeStatus.subscribed) {
      (dropped ? onRejoined : onReady)?.call();
      dropped = false;
    } else if (status == RealtimeSubscribeStatus.channelError || status == RealtimeSubscribeStatus.timedOut) {
      dropped = true;
      onError(error ?? StateError('realtime ${status.name}'));
    }
  };
}

/// 서버가 postgres_changes 구독을 만들었다는 `system` 이벤트에 흔히 실리는 문구. 실기기 값은 아직 못 봤다(E-CHAT-67 진단 대기) —
/// 모양이 다르면 아래 [isPostgresReady] 만 고치면 된다.
/// 참고: 둘째 문구('Replication connection established')는 지금은 사실상 죽은 코드다 — 우리 채널은 `RealtimeChannelConfig(replicationReady: true)`
/// 옵션 없이 만들어서 서버가 그 system 이벤트를 안 보낸다. 그 옵션을 켤 때 쓰인다.
const List<String> _postgresReadyMessages = [
  'Subscribed to PostgreSQL', // Realtime 서버가 postgres_changes 구독을 만들면 보내는 알림
  'Replication connection established', // `RealtimeChannelConfig.replicationReady` 를 켠 채널의 복제 연결 알림
];

/// `system` 이벤트 [payload] 가 "postgres_changes 구독이 서버에 만들어졌다(status ok)" 인가.
/// 서버가 보낸 값이라 어떤 모양이 와도 던지지 않는다 — Map 이 아니거나 status 가 ok 가 아니면 모두 false.
/// 실패(status error)는 여기서 다루지 않는다 — realtime_client 가 이미 `channelError` 로 올린다.
bool isPostgresReady(Object? payload) {
  if (payload is! Map || payload['status'] != 'ok') {
    return false;
  }
  final message = payload['message'];
  return payload['extension'] == 'postgres_changes' ||
      (message is String && _postgresReadyMessages.any(message.contains));
}

/// 채널의 `system` 이벤트를 받는 쪽 신호로 바꾼다 — [isPostgresReady] 인 이벤트마다 [onReady]. 같은 이벤트가 여러 번 와도
/// 그만큼 부른다(멱등은 받는 쪽 몫). [onReady] 가 없거나 이벤트 모양이 이상해도 던지지 않는다.
void Function(dynamic) systemEventListener(void Function()? onReady) {
  return (payload) {
    if (isPostgresReady(payload)) {
      onReady?.call();
    }
  };
}

/// Supabase Realtime 구현. 읽기 권한은 ERD §2 가 `messages` 에 걸어 둔 RLS 를 그대로 물려받는다 —
/// 나간 사람은 구독해도 아무 줄도 받지 못한다.
class RealtimeMessageStream implements MessageStream {
  const RealtimeMessageStream(this._client);

  final SupabaseClient _client;

  @override
  Stream<Message> subscribe(String matchId, {void Function()? onRejoined, void Function()? onReady}) {
    RealtimeChannel? channel;
    late final StreamController<Message> controller;
    controller = StreamController<Message>(
      onListen: () {
        channel = _client
            .channel('messages:$matchId')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'messages',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'match_id',
                value: matchId,
              ),
              // 모르는 종류면 [Message.fromJson] 이 null 을 준다 — 그 줄만 흘려보낸다.
              callback: (payload) {
                final message = Message.fromJson(payload.newRecord);
                if (message != null) {
                  controller.add(message);
                }
              },
            )
            // 서버가 postgres_changes 구독을 만들었다고 알리면 준비됨 — 이 걸이는 구독 전에 걸어야 하고,
            // realtime_client 가 subscribe() 안에서 error 를 channelError 로 올리는 걸이와는 별개다.
            .onSystemEvents(systemEventListener(onReady))
            .subscribe(
              channelStatusListener(onError: controller.addError, onRejoined: onRejoined, onReady: onReady),
            );
      },
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
}
