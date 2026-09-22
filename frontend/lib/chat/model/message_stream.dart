import 'dart:async';

import 'package:campus_mate/chat/model/message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 방을 열고 있는 동안 새 메시지를 밀어 주는 통로.
/// **Realtime 을 이 뒤에 숨긴다** — 테스트는 가짜를 끼우고 Supabase 를 켜지 않는다
/// (조각 4 의 `PushMessaging` 과 같은 경계).
abstract interface class MessageStream {
  /// 구독을 끊으면 채널도 닫힌다. 목록 화면은 구독하지 않는다(푸시 + 당겨서 새로고침).
  Stream<Message> subscribe(String matchId);
}

/// Supabase Realtime 구현. 읽기 권한은 ERD §2 가 `messages` 에 걸어 둔 RLS 를 그대로 물려받는다 —
/// 나간 사람은 구독해도 아무 줄도 받지 못한다.
class RealtimeMessageStream implements MessageStream {
  const RealtimeMessageStream(this._client);

  final SupabaseClient _client;

  @override
  Stream<Message> subscribe(String matchId) {
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
            .subscribe();
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
