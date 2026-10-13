import 'dart:async';

import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/chat/model/message.dart';
import 'package:campus_mate/chat/model/user_event_stream.dart';
import 'package:campus_mate/chat/viewmodel/conversations_ui_state.dart';
import 'package:campus_mate/chat/viewmodel/conversations_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_chat_repository.dart';

void main() {
  late FakeChatRepository chat;
  late ProviderContainer container;

  setUp(() {
    chat = FakeChatRepository()..conversations = Success([conversationFixture(unreadCount: 2)]);
    container = ProviderContainer(overrides: [chatRepositoryProvider.overrideWithValue(chat)]);
    addTearDown(container.dispose);
  });

  ConversationsViewModel viewModel() => container.read(conversationsViewModelProvider.notifier);
  ConversationsUiState stateNow() => container.read(conversationsViewModelProvider);

  /// 이미 한 번 읽어 줄이 보이는 상태에서 시작한다.
  Future<void> readOnce() async {
    await viewModel().refresh();
    expect(stateNow().conversations, hasLength(1));
  }

  test('조용한 재읽기가 실패해도 있던 대화 줄은 남고 오류 문구는 새로 생기지 않는다', () async {
    await readOnce();
    chat.conversations = const FailureResult(NetworkFailure());

    await viewModel().refresh(quiet: true);

    expect(stateNow().conversations, hasLength(1));
    expect(stateNow().errorMessage, isNull);
  });

  test('아직 한 번도 못 읽은 상태의 조용한 읽기 실패는 로딩을 끝내고 오류를 보인다', () async {
    chat.conversations = const FailureResult(NetworkFailure());

    await viewModel().refresh(quiet: true);

    expect(stateNow().isLoading, isFalse);
    expect(stateNow().errorMessage, const NetworkFailure().toDisplayMessage());
  });

  test('당겨서 새로고침(조용하지 않은 읽기)이 실패하면 오류를 보이고 줄은 남는다', () async {
    await readOnce();
    chat.conversations = const FailureResult(NetworkFailure());

    await viewModel().refresh();

    expect(stateNow().conversations, hasLength(1));
    expect(stateNow().errorMessage, const NetworkFailure().toDisplayMessage());
  });

  test('조용한 재읽기가 성공하면 새 목록으로 바꾸고 이전 오류 문구를 지운다', () async {
    await readOnce();
    chat.conversations = const FailureResult(NetworkFailure());
    await viewModel().refresh();
    chat.conversations = Success([conversationFixture(unreadCount: 7)]);

    await viewModel().refresh(quiet: true);

    expect(stateNow().unreadTotal, 7);
    expect(stateNow().errorMessage, isNull);
  });

  group('읽는 중에 겹친 읽기', () {
    /// 조용한 읽기가 서버 답을 기다리는 중이다. 이 읽기는 실패로 끝나게 해 둔다.
    Future<void> startQuietReadThatWillFail() async {
      await readOnce();
      chat.holdConversations = Completer<void>();
      chat.conversations = const FailureResult(NetworkFailure());
      unawaited(viewModel().refresh(quiet: true));
      await pumpEventQueue();
    }

    test('당겨서 새로고침이 진행 중인 조용한 읽기에 합쳐진 뒤 실패하면 오류 문구를 보인다', () async {
      await startQuietReadThatWillFail();
      final before = chat.conversationsFetchCount;

      final pulled = viewModel().refresh();
      chat.holdConversations!.complete();
      await pulled;

      expect(chat.conversationsFetchCount, before + 1);
      expect(stateNow().conversations, hasLength(1));
      expect(stateNow().errorMessage, const NetworkFailure().toDisplayMessage());
    });

    test('조용하지 않은 호출이 여러 번 합쳐져도 끝난 뒤 다시 읽는 건 한 번이다', () async {
      await startQuietReadThatWillFail();
      final before = chat.conversationsFetchCount;

      final first = viewModel().refresh();
      final second = viewModel().refresh();
      chat.holdConversations!.complete();
      await Future.wait([first, second]);

      expect(chat.conversationsFetchCount, before + 1);
    });

    test('합쳐진 호출이 돌려받은 Future 는 다시 읽기까지 끝난 뒤에 완료된다', () async {
      await readOnce();
      chat.holdConversations = Completer<void>();
      unawaited(viewModel().refresh(quiet: true));
      await pumpEventQueue();
      final before = chat.conversationsFetchCount;
      var done = false;

      final joined = viewModel().refresh().then((_) => done = true);
      chat.holdConversations!.complete();
      await joined;

      expect(done, isTrue);
      // 읽기가 둘 다 끝난 뒤여야 한다 — 첫 읽기만 끝났을 때 풀렸다면 여기서 before 이다.
      expect(chat.conversationsFetchCount, before + 1);
      expect(stateNow().isLoading, isFalse);
    });

    test('조용한 호출이 합쳐지는 건 다시 읽기를 만들지 않는다', () async {
      await readOnce();
      chat.holdConversations = Completer<void>();
      unawaited(viewModel().refresh(quiet: true));
      await pumpEventQueue();
      final before = chat.conversationsFetchCount;

      final joined = viewModel().refresh(quiet: true);
      chat.holdConversations!.complete();
      await joined;
      await pumpEventQueue();

      expect(chat.conversationsFetchCount, before);
    });

    test('처음 열 때 화면의 조용한 읽기와 뷰모델의 첫 읽기가 합쳐져도 한 번만 읽는다', () async {
      // 화면 initState 와 같다 — 뷰모델이 만들어지는 순간 첫 읽기가 예약되고, 곧바로 조용한 읽기가 먼저 시작된다.
      unawaited(viewModel().refresh(quiet: true));
      await pumpEventQueue();

      expect(chat.conversationsFetchCount, 1);
      expect(stateNow().isLoading, isFalse);
    });
  });

  // 사용자 채널(설계안 A)의 message 이벤트를 목록에 바로 반영한다. 서버 값이 기준이라 다음 읽기가 덮어쓴다.
  group('사용자 채널 message 로 목록을 바로 고친다', () {
    final listAt = DateTime(2026, 10, 13, 14);

    MessageEvent event({
      String matchId = 'm1',
      String id = 'msg-new',
      String senderId = partnerId,
      int minute = 1,
      MessageKind kind = MessageKind.text,
    }) =>
        MessageEvent(
          matchId,
          messageFixture(id: id, senderId: senderId, kind: kind, body: '새 줄 $id', createdAt: listAt.add(Duration(minutes: minute))),
        );

    Future<void> readTwoRooms() async {
      chat.conversations = Success([
        conversationFixture(unreadCount: 1, lastMessageAt: listAt),
        conversationFixture(matchId: 'm2', nickname: '두번째', unreadCount: 0, lastMessageAt: listAt.subtract(const Duration(hours: 1))),
      ]);
      await viewModel().refresh();
    }

    void apply(MessageEvent event, {bool seen = false}) => viewModel().applyMessage(event, myId: myId, seen: seen);

    test('상대 줄은 마지막 줄 · 시각 · 안 읽은 수를 바꾸고 그 방을 맨 위로 올린다', () async {
      await readTwoRooms();

      apply(event(matchId: 'm2', minute: 5));

      final rows = stateNow().conversations;
      expect(rows.map((row) => row.matchId), ['m2', 'm1']);
      expect((rows.first.lastMessage, rows.first.unreadCount, rows.first.lastMessageKind), ('새 줄 msg-new', 1, MessageKind.text));
      expect(rows.first.lastMessageAt, listAt.add(const Duration(minutes: 5)));
      expect(stateNow().unreadTotal, 2);
    });

    test('내가 보낸 줄은 안 읽은 수를 올리지 않는다', () async {
      await readTwoRooms();

      apply(event(senderId: myId));

      expect((stateNow().conversations.first.lastMessage, stateNow().unreadTotal), ('새 줄 msg-new', 1));
    });

    test('같은 줄(같은 message.id)이 두 번 와도 한 번만 센다', () async {
      await readTwoRooms();

      apply(event());
      apply(event());

      expect(stateNow().conversations.first.unreadCount, 2);
    });

    test('서버 목록이 이미 반영한 줄(마지막 줄보다 늦지 않은 줄)은 다시 세지 않는다 — 뒤늦게 온 이벤트', () async {
      await readTwoRooms();

      apply(event(minute: 0));
      apply(event(id: 'older', minute: -3));

      expect((stateNow().conversations.first.unreadCount, stateNow().conversations.first.lastMessage), (1, '내일 시간 괜찮으세요?'));
    });

    test('지금 그 방을 보고 있으면 마지막 줄만 바꾸고 안 읽은 수는 올리지 않는다', () async {
      await readTwoRooms();

      apply(event(), seen: true);

      expect((stateNow().conversations.first.lastMessage, stateNow().unreadTotal), ('새 줄 msg-new', 1));
    });

    test('나가기 · 차단 줄(left)도 마지막 줄로 보인다', () async {
      await readTwoRooms();

      apply(event(kind: MessageKind.left));

      expect(stateNow().conversations.first.lastMessageKind, MessageKind.left);
    });

    test('목록에 없는 방이면 목록을 조용히 다시 읽는다', () async {
      await readTwoRooms();
      final before = chat.conversationsFetchCount;
      chat.conversations = const FailureResult(NetworkFailure());

      apply(event(matchId: 'm-unknown'));
      await pumpEventQueue();

      expect(chat.conversationsFetchCount, before + 1);
      expect(stateNow().errorMessage, isNull);
    });

    test('떠 있던 오류 줄은 그대로 둔다 — 사용자가 누른 일이 아니다', () async {
      await readTwoRooms();
      chat.conversations = const FailureResult(NetworkFailure());
      await viewModel().refresh();

      apply(event());

      expect(stateNow().errorMessage, const NetworkFailure().toDisplayMessage());
    });

    // 이벤트 직전에 출발한 읽기는 그 줄을 못 봤을 수 있다 — 그 결과가 이벤트를 덮으면 다음 읽기 전까지 한 줄이 빈다.
    test('읽는 중에 온 이벤트는 그 읽기가 끝난 뒤 조용히 한 번 더 읽어 서버 값으로 맞춘다', () async {
      await readTwoRooms();
      chat.holdConversations = Completer<void>();
      unawaited(viewModel().refresh(quiet: true));
      await pumpEventQueue();
      final before = chat.conversationsFetchCount;

      apply(event());
      chat.conversations = const FailureResult(NetworkFailure());
      chat.holdConversations!.complete();
      chat.holdConversations = null;
      await pumpEventQueue();

      expect(chat.conversationsFetchCount, before + 1);
      expect(stateNow().errorMessage, isNull);
    });
  });
}
