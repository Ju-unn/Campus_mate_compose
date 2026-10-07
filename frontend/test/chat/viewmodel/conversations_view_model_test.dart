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
}
