import 'package:campus_mate/chat/model/message.dart';
import 'package:campus_mate/chat/model/user_event_stream.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockClient extends Mock implements SupabaseClient {}

class _MockChannel extends Mock implements RealtimeChannel {}

/// 서버(PR #508)가 `user:<내 id>` 비공개 채널로 쏘는 이벤트 3종(설계안 A). Dart `onBroadcast` 콜백은
/// `{type, event, payload}` 전체를 주고 우리 값은 그 안의 `payload` 다.
Map<String, dynamic> _broadcast(String event, Object? payload) =>
    {'type': 'broadcast', 'event': event, 'payload': payload};

Map<String, dynamic> _messagePayload({String kind = 'text', String senderId = 'p2'}) => {
      'match_id': 'm1',
      'message': {
        'id': 'msg-9',
        'sender_id': senderId,
        'kind': kind,
        'body': '안녕하세요',
        'created_at': '2026-10-13T05:00:00.123456+00:00',
      },
    };

void main() {
  group('UserEvent.fromBroadcast — 서버 이벤트를 타입 있는 값으로', () {
    test('message 는 방 id 와 메시지 한 통이다', () {
      final event = UserEvent.fromBroadcast(_broadcast('message', _messagePayload()));

      expect(event, isA<MessageEvent>());
      final message = (event! as MessageEvent).message;
      expect(event.matchId, 'm1');
      expect((message.id, message.senderId, message.kind, message.body), ('msg-9', 'p2', MessageKind.text, '안녕하세요'));
      expect(message.createdAt.isAtSameMomentAs(DateTime.utc(2026, 10, 13, 5, 0, 0, 123, 456)), isTrue);
    });

    test('나가기 · 차단 줄도 kind=left 인 message 로 온다', () {
      final event = UserEvent.fromBroadcast(_broadcast('message', _messagePayload(kind: 'left')));

      expect((event! as MessageEvent).message.kind, MessageKind.left);
    });

    // 서버 읽음 시각은 +09:00, DB 시각은 +00:00 으로 올 수 있다 — 문자열이 아니라 같은 순간으로 읽어야 비교가 맞다.
    test('read 는 읽은 사람과 시각이다 — +09:00 시각도 같은 순간으로 읽는다', () {
      final event = UserEvent.fromBroadcast(_broadcast('read', {
        'match_id': 'm1',
        'reader_id': 'p2',
        'last_read_at': '2026-10-13T14:00:00.5+09:00',
      }));

      expect(event, isA<ReadEvent>());
      final read = event! as ReadEvent;
      expect((read.matchId, read.readerId), ('m1', 'p2'));
      expect(read.readAt.isAtSameMomentAs(DateTime.utc(2026, 10, 13, 5, 0, 0, 500)), isTrue);
    });

    test('room_changed 는 방 id 만 쓴다(이유는 보지 않고 목록을 다시 읽는다)', () {
      final event = UserEvent.fromBroadcast(_broadcast('room_changed', {'match_id': 'm7', 'reason': 'closed'}));

      expect(event, isA<RoomChangedEvent>());
      expect(event!.matchId, 'm7');
    });

    test('모르는 이벤트 · 모르는 메시지 종류 · 모양이 이상한 값은 던지지 않고 null 이다', () {
      final weird = <Map<String, dynamic>>[
        _broadcast('typing', {'match_id': 'm1'}),
        _broadcast('message', _messagePayload(kind: 'sticker')),
        _broadcast('message', {'match_id': 'm1'}),
        _broadcast('message', {'match_id': 'm1', 'message': 'text'}),
        _broadcast('message', {'message': _messagePayload()['message']}),
        _broadcast('read', {'match_id': 'm1', 'reader_id': 'p2', 'last_read_at': 'not-a-time'}),
        _broadcast('read', {'match_id': 'm1', 'reader_id': 7, 'last_read_at': '2026-10-13T05:00:00Z'}),
        _broadcast('room_changed', null),
        _broadcast('room_changed', 'm1'),
        {'type': 'broadcast', 'payload': {'match_id': 'm1'}},
        <String, dynamic>{},
      ];

      for (final broadcast in weird) {
        expect(UserEvent.fromBroadcast(broadcast), isNull, reason: '$broadcast');
      }
    });
  });

  group('RealtimeUserEventStream — 가짜 채널로 본 배선', () {
    late _MockClient client;
    late _MockChannel channel;
    late Map<String, void Function(Map<String, dynamic>)> broadcasts;
    late void Function(RealtimeSubscribeStatus, Object?) status;
    RealtimeChannelConfig? opened;

    setUpAll(() {
      registerFallbackValue(const RealtimeChannelConfig());
      registerFallbackValue(_MockChannel());
    });

    setUp(() {
      client = _MockClient();
      channel = _MockChannel();
      broadcasts = {};
      opened = null;
      when(() => client.channel(any(), opts: any(named: 'opts'))).thenAnswer((invocation) {
        opened = invocation.namedArguments[#opts] as RealtimeChannelConfig;
        return channel;
      });
      when(() => channel.onBroadcast(event: any(named: 'event'), callback: any(named: 'callback')))
          .thenAnswer((invocation) {
        broadcasts[invocation.namedArguments[#event] as String] =
            invocation.namedArguments[#callback] as void Function(Map<String, dynamic>);
        return channel;
      });
      when(() => channel.subscribe(any())).thenAnswer((invocation) {
        status = invocation.positionalArguments.first as void Function(RealtimeSubscribeStatus, Object?);
        return channel;
      });
      when(() => client.removeChannel(any())).thenAnswer((_) async => 'ok');
    });

    test('내 id 의 user: 채널을 private 으로 연다 — public 은 같은 이름이라도 다른 채널이라 아무것도 안 온다', () {
      RealtimeUserEventStream(client).subscribe('u1').listen((_) {});

      verify(() => client.channel('user:u1', opts: any(named: 'opts'))).called(1);
      expect(opened!.private, isTrue);
      expect(broadcasts.keys, containsAll(['message', 'read', 'room_changed']));
    });

    test('Broadcast 콜백이 준 맵 전체에서 payload 를 읽어 이벤트로 흘리고, 모르는 모양은 버린다', () async {
      final events = <UserEvent>[];
      RealtimeUserEventStream(client).subscribe('u1').listen(events.add);

      broadcasts['message']!(_broadcast('message', _messagePayload()));
      broadcasts['message']!(_broadcast('message', _messagePayload(kind: 'sticker')));
      broadcasts['read']!(_broadcast('read', {'match_id': 'm1', 'reader_id': 'p2', 'last_read_at': '2026-10-13T05:00:00Z'}));
      broadcasts['room_changed']!(_broadcast('room_changed', {'match_id': 'm1', 'reason': 'matched'}));
      await pumpEventQueue();

      expect(events.map((event) => event.runtimeType), [MessageEvent, ReadEvent, RoomChangedEvent]);
    });

    test('서버가 입장을 받아 주면(SUBSCRIBED) 붙음을 알린다 — 다시 붙어도 매번', () {
      var subscribed = 0;
      RealtimeUserEventStream(client).subscribe('u1', onSubscribed: () => subscribed++).listen((_) {});

      status(RealtimeSubscribeStatus.subscribed, null);
      status(RealtimeSubscribeStatus.subscribed, null);

      expect(subscribed, 2);
    });

    // 정책이 없으면 입장이 거부된다(channelError). 서버가 채널을 닫아도(토큰 만료 → phx_close) 더는 이벤트가 안 온다.
    test('입장 거부 · 타임아웃 · 서버가 닫음은 모두 스트림 오류다', () async {
      final errors = <Object>[];
      RealtimeUserEventStream(client).subscribe('u1').listen((_) {}, onError: errors.add);

      status(RealtimeSubscribeStatus.channelError, Exception('Unauthorized'));
      status(RealtimeSubscribeStatus.timedOut, null);
      status(RealtimeSubscribeStatus.closed, null);
      await pumpEventQueue();

      expect(errors, hasLength(3));
    });

    test('구독을 끊으면 채널을 지우고, 그 뒤 오는 closed 는 오류로 올리지 않는다', () async {
      final errors = <Object>[];
      final subscription = RealtimeUserEventStream(client).subscribe('u1').listen((_) {}, onError: errors.add);

      await subscription.cancel();
      status(RealtimeSubscribeStatus.closed, null);
      broadcasts['message']!(_broadcast('message', _messagePayload()));
      await pumpEventQueue();

      verify(() => client.removeChannel(channel)).called(1);
      expect(errors, isEmpty);
    });

    test('구독하기 전에는 채널을 열지 않는다', () {
      RealtimeUserEventStream(client).subscribe('u1');

      verifyNever(() => client.channel(any(), opts: any(named: 'opts')));
    });
  });
}
