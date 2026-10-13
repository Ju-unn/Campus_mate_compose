import 'dart:async';

import 'package:campus_mate/chat/model/chat_repository.dart';
import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/chat/model/chat_room.dart';
import 'package:campus_mate/chat/model/message.dart';
import 'package:campus_mate/chat/model/user_event_stream.dart';
import 'package:campus_mate/chat/viewmodel/chat_room_view_model.dart';
import 'package:campus_mate/chat/viewmodel/conversations_view_model.dart';
import 'package:campus_mate/chat/viewmodel/user_channel.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../matching/model/fake_card_repository.dart';
import '../model/fake_chat_repository.dart';

/// 앱이 앞에 있는 동안 내 우편함 채널 `user:<내 id>` 하나를 듣는다(설계안 A 4단계).
void main() {
  late FakeChatRepository chat;
  late FakeCardRepository cards;
  late FakeUserEventStream events;
  late FakeMessageStream roomStream;
  final listAt = DateTime(2026, 10, 13, 14);
  final sentAt = DateTime(2026, 10, 13, 13);

  setUp(() {
    chat = FakeChatRepository()
      ..conversations = Success([conversationFixture(unreadCount: 1, lastMessageAt: listAt)])
      ..room = Success(roomFixture(partnerRead: const PartnerRead.known(null)))
      ..messages = Success(MessagePage(
        messages: [messageFixture(id: 'mine-1', senderId: myId, createdAt: sentAt)],
        hasMore: false,
      ));
    cards = FakeCardRepository();
    events = FakeUserEventStream();
    roomStream = FakeMessageStream();
  });

  ProviderContainer containerFor() {
    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(chat),
      cardRepositoryProvider.overrideWithValue(cards),
      userEventStreamProvider.overrideWithValue(events),
      messageStreamProvider.overrideWithValue(roomStream),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  UserChannel channelOf(ProviderContainer container) => container.read(userChannelProvider.notifier);
  bool liveOf(ProviderContainer container) => container.read(userChannelProvider);

  /// 목록이 한 번 읽혀 있고 채널이 붙은 상태.
  Future<ProviderContainer> live() async {
    final container = containerFor();
    await container.read(conversationsViewModelProvider.notifier).refresh();
    channelOf(container).start(myId);
    events.connect();
    await pumpEventQueue();
    return container;
  }

  Message incoming({String id = 'msg-new', String senderId = partnerId, int minute = 1}) => messageFixture(
        id: id,
        senderId: senderId,
        body: '새 줄 $id',
        createdAt: listAt.add(Duration(minutes: minute)),
      );

  group('구독 수명', () {
    test('시작하면 내 id 로 채널 하나를 열고, 서버가 받아 주기 전에는 연결 안 됨이다', () {
      final container = containerFor();

      channelOf(container).start(myId);

      expect(events.subscribed, [myId]);
      expect(liveOf(container), isFalse);
    });

    test('붙으면 연결됨이 되고 대화 · 받은 신청 · 보낸 신청을 한 번 다시 읽는다 — 끊긴 동안 놓친 이벤트 복구', () async {
      final container = containerFor();
      await container.read(conversationsViewModelProvider.notifier).refresh();
      final before = (chat.conversationsFetchCount, cards.fetchAcceptancesCount, cards.fetchSentCount);
      channelOf(container).start(myId);

      events.connect();
      await pumpEventQueue();

      expect(liveOf(container), isTrue);
      expect(
        (chat.conversationsFetchCount, cards.fetchAcceptancesCount, cards.fetchSentCount),
        (before.$1 + 1, before.$2 + 1, before.$3 + 1),
      );
    });

    // 앱 복귀: onShow 가 채널을 걸고 바로 onResume 의 목록 읽기(refreshOnResume)가 출발한다. 그 읽기는 채널이 붙기 **전의**
    // 서버를 본다 — 그 사이 들어온 줄은 읽기에도 이벤트에도 없다. 겹쳐 부르지는 않되 끝난 뒤 한 번 더 읽어야 메워진다.
    test('붙는 순간 이미 읽는 중이던 목록이 있으면 겹쳐 읽지 않고, 그 읽기가 끝난 뒤 조용히 한 번 더 읽는다', () async {
      final container = containerFor();
      final conversations = container.read(conversationsViewModelProvider.notifier);
      await conversations.refresh();
      chat.holdConversations = Completer<void>();
      unawaited(conversations.refresh(quiet: true));
      await pumpEventQueue();
      final before = chat.conversationsFetchCount;
      channelOf(container).start(myId);

      events.connect();
      await pumpEventQueue();
      expect(chat.conversationsFetchCount, before, reason: '읽는 중에는 겹쳐 부르지 않는다');
      chat.holdConversations!.complete();
      chat.holdConversations = null;
      await pumpEventQueue();

      expect(chat.conversationsFetchCount, before + 1);
      expect(container.read(conversationsViewModelProvider).errorMessage, isNull);
    });

    test('같은 사람으로 또 시작해도(관문 · 세션 알림이 여러 번 온다) 채널을 더 열지 않는다', () async {
      final container = await live();

      channelOf(container).start(myId);

      expect(events.subscribed, [myId]);
      expect(liveOf(container), isTrue);
    });

    test('멈추면(앱이 뒤로) 채널을 닫고 연결 안 됨이다 — 다시 시작하면(앱이 앞으로) 새로 열고 붙으면 다시 읽는다', () async {
      final container = await live();

      channelOf(container).stop();
      expect((liveOf(container), events.openCount), (false, 0));

      final before = chat.conversationsFetchCount;
      channelOf(container).start(myId);
      events.connect();
      await pumpEventQueue();

      expect(events.subscribed, [myId, myId]);
      expect(liveOf(container), isTrue);
      expect(chat.conversationsFetchCount, before + 1);
    });

    test('다른 계정으로 시작하면 앞 사람 채널을 닫고 새 id 로 연다', () async {
      final container = await live();

      channelOf(container).start('someone-else');

      expect(events.subscribed, [myId, 'someone-else']);
      expect((events.openCount, liveOf(container)), (1, false));
    });

    test('로그아웃하면(SessionScope 가 컨테이너째 버린다) 채널을 닫는다', () async {
      final container = await live();

      container.dispose();

      expect(events.openCount, 0);
    });
  });

  group('구독 실패 · 끊김 — 조용히, 지수 백오프로 다시', () {
    testWidgets('거부되면(정책 적용 전) 연결 안 됨으로 두고 2초 뒤 다시 — 실패가 이어지면 두 배씩 늘다 5분에서 멈춘다', (tester) async {
      final container = containerFor();
      channelOf(container).start(myId);
      events.fail();
      await tester.pump();
      expect((liveOf(container), events.openCount), (false, 0));

      var attempts = 1;
      for (final seconds in [2, 4, 8, 16, 32, 64, 128, 256, 300, 300]) {
        await tester.pump(Duration(seconds: seconds) - const Duration(milliseconds: 1));
        expect(events.subscribed, hasLength(attempts), reason: '$seconds초 전에는 다시 열지 않는다');
        await tester.pump(const Duration(milliseconds: 1));
        expect(events.subscribed, hasLength(++attempts), reason: '$seconds초에 다시 연다');
        events.fail();
        await tester.pump();
      }
      expect(userChannelRetryFirst, const Duration(seconds: 2));
      expect(userChannelRetryMax, const Duration(minutes: 5));
      container.dispose();
    });

    testWidgets('붙으면 간격이 처음(2초)으로 돌아간다', (tester) async {
      final container = containerFor();
      channelOf(container).start(myId);
      events.fail();
      await tester.pump(const Duration(seconds: 2));
      events.fail();
      await tester.pump(const Duration(seconds: 4));
      expect(events.subscribed, hasLength(3));

      events.connect();
      await tester.pump();
      expect(liveOf(container), isTrue);
      events.fail();
      await tester.pump(userChannelRetryFirst);

      expect(events.subscribed, hasLength(4));
      container.dispose();
    });

    testWidgets('붙은 뒤 끊기면 연결 안 됨으로 바뀌고 채널을 닫은 뒤 2초 뒤 다시 연다', (tester) async {
      final container = containerFor();
      channelOf(container).start(myId);
      events.connect();
      await tester.pump();
      expect(liveOf(container), isTrue);

      events.fail();
      await tester.pump();
      expect((liveOf(container), events.openCount), (false, 0));

      await tester.pump(userChannelRetryFirst);
      events.connect();
      await tester.pump();
      expect((events.subscribed.length, liveOf(container)), (2, true));
      container.dispose();
    });

    testWidgets('기다리는 동안 또 시작을 불러도 바로 다시 열지 않는다 — 폭주 방지', (tester) async {
      final container = containerFor();
      channelOf(container).start(myId);
      events.fail();
      await tester.pump();

      channelOf(container).start(myId);
      channelOf(container).start(myId);
      expect(events.subscribed, hasLength(1));

      await tester.pump(userChannelRetryFirst);
      expect(events.subscribed, hasLength(2));
      container.dispose();
    });

    testWidgets('앱이 뒤로 가면 기다리던 재시도도 멈추고, 돌아오면 바로 한 번 시도하되 늘어난 간격은 그대로다', (tester) async {
      final container = containerFor();
      channelOf(container).start(myId);
      events.fail();
      await tester.pump();

      channelOf(container).stop();
      await tester.pump(const Duration(minutes: 10));
      expect(events.subscribed, hasLength(1));

      channelOf(container).start(myId);
      expect(events.subscribed, hasLength(2));
      events.fail();
      await tester.pump(const Duration(seconds: 4) - const Duration(milliseconds: 1));
      expect(events.subscribed, hasLength(2));
      await tester.pump(const Duration(milliseconds: 1));
      expect(events.subscribed, hasLength(3));
      container.dispose();
    });

    testWidgets('로그아웃하면 기다리던 재시도도 정리한다', (tester) async {
      final container = containerFor();
      channelOf(container).start(myId);
      events.fail();
      await tester.pump();

      container.dispose();
      await tester.pump(const Duration(minutes: 10));

      expect(events.subscribed, hasLength(1));
    });

    testWidgets('닫은 옛 구독이 늦게 뱉는 붙음 신호는 버린다', (tester) async {
      final container = containerFor();
      channelOf(container).start(myId);
      events.fail();
      await tester.pump(userChannelRetryFirst);

      events.connect(subscription: 0);
      await tester.pump();

      expect(liveOf(container), isFalse);
      container.dispose();
    });
  });

  group('이벤트 나눠 주기', () {
    test('상대 message 는 목록의 마지막 줄 · 시각 · 안 읽은 수와 하단 내비 배지를 바로 바꾼다', () async {
      final container = await live();

      events.push(MessageEvent('m1', incoming()));
      await pumpEventQueue();

      final row = container.read(conversationsViewModelProvider).conversations.single;
      expect((row.lastMessage, row.unreadCount), ('새 줄 msg-new', 2));
      expect(row.lastMessageAt, listAt.add(const Duration(minutes: 1)));
      expect(container.read(chatBadgeCountProvider), 2);
    });

    test('내가(다른 기기에서) 보낸 message 는 마지막 줄만 바꾸고 안 읽은 수는 그대로다', () async {
      final container = await live();

      events.push(MessageEvent('m1', incoming(senderId: myId)));
      await pumpEventQueue();

      final row = container.read(conversationsViewModelProvider).conversations.single;
      expect((row.lastMessage, row.unreadCount), ('새 줄 msg-new', 1));
    });

    test('room_changed 는 대화 · 받은 신청 · 보낸 신청을 다시 읽는다', () async {
      final container = await live();
      final before = (chat.conversationsFetchCount, cards.fetchAcceptancesCount, cards.fetchSentCount);

      events.push(const RoomChangedEvent('m9'));
      await pumpEventQueue();

      expect(
        (chat.conversationsFetchCount, cards.fetchAcceptancesCount, cards.fetchSentCount),
        (before.$1 + 1, before.$2 + 1, before.$3 + 1),
      );
      expect(liveOf(container), isTrue);
    });

    group('열린 방', () {
      Future<ProviderContainer> liveWithOpenRoom() async {
        final container = await live();
        container.listen(chatRoomViewModelProvider('m1'), (_, _) {});
        await pumpEventQueue();
        return container;
      }

      bool hasUnread(ProviderContainer container) {
        final room = container.read(chatRoomViewModelProvider('m1'));
        return room.messages.any(room.isUnreadByPartner);
      }

      test('read 가 오면 열린 방의 내 줄 1 이 폴링을 기다리지 않고 바로 사라진다', () async {
        final container = await liveWithOpenRoom();
        expect(hasUnread(container), isTrue);

        events.push(ReadEvent('m1', readerId: partnerId, readAt: sentAt.add(const Duration(seconds: 1))));
        await pumpEventQueue();

        expect(hasUnread(container), isFalse);
      });

      test('열려 있지 않은 방의 read 는 그 방 뷰모델을 새로 만들지 않는다', () async {
        final container = await live();

        events.push(ReadEvent('m5', readerId: partnerId, readAt: sentAt));
        await pumpEventQueue();

        expect(container.exists(chatRoomViewModelProvider('m5')), isFalse);
      });

      test('지금 보고 있는 방의 상대 줄은 방에 바로 붙고 목록의 안 읽은 수를 올리지 않는다 — 안 보이면 올린다', () async {
        final container = await liveWithOpenRoom();
        final unreadBefore = container.read(conversationsViewModelProvider).conversations.single.unreadCount;

        events.push(MessageEvent('m1', incoming()));
        await pumpEventQueue();
        expect(container.read(chatRoomViewModelProvider('m1')).messages.map((m) => m.id), contains('msg-new'));
        expect(container.read(conversationsViewModelProvider).conversations.single.unreadCount, unreadBefore);

        container.read(chatRoomViewModelProvider('m1').notifier).setVisible(false);
        events.push(MessageEvent('m1', incoming(id: 'msg-hidden', minute: 2)));
        await pumpEventQueue();
        expect(container.read(conversationsViewModelProvider).conversations.single.unreadCount, unreadBefore + 1);
      });

      test('방 채널과 사용자 채널로 같은 줄이 두 번 와도 방에는 한 번만 그린다', () async {
        final container = await liveWithOpenRoom();

        roomStream.push(incoming());
        events.push(MessageEvent('m1', incoming()));
        await pumpEventQueue();

        final ids = container.read(chatRoomViewModelProvider('m1')).messages.map((m) => m.id);
        expect(ids.where((id) => id == 'msg-new'), hasLength(1));
      });
    });
  });
}
