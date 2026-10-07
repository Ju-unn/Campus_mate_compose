import 'dart:async';

import 'package:campus_mate/chat/model/chat_repository_provider.dart';
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
}
