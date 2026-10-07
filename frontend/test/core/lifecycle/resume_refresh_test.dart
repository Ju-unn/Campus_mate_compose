import 'dart:async';

import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/chat/viewmodel/conversations_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/lifecycle/resume_refresh.dart';
import 'package:campus_mate/core/push/push_refresh.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/viewmodel/acceptances_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../chat/model/fake_chat_repository.dart';
import '../../matching/model/fake_card_repository.dart';

void main() {
  late FakeChatRepository chat;
  late FakeCardRepository cards;
  late ProviderContainer container;

  setUp(() {
    chat = FakeChatRepository()..conversations = Success([conversationFixture(unreadCount: 2)]);
    cards = FakeCardRepository();
    container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(chat),
      cardRepositoryProvider.overrideWithValue(cards),
    ]);
    addTearDown(container.dispose);
  });

  void resume({bool isAuthenticated = true, VerificationGate gate = VerificationGate.complete}) =>
      refreshOnResume(container.read, isAuthenticated: isAuthenticated, gate: gate);

  /// 두 목록이 이미 한 번 읽혀 화면에 줄이 있는 상태에서 시작한다.
  Future<void> warmUp() async {
    await container.read(conversationsViewModelProvider.notifier).refresh();
    await container.read(acceptancesViewModelProvider.notifier).refresh();
  }

  test('로그인했고 관문이 끝났으면 대화 목록과 수락 대기를 다시 읽는다', () async {
    await warmUp();
    final chatBefore = chat.conversationsFetchCount;
    final cardsBefore = cards.fetchAcceptancesCount;
    chat.conversations = Success([conversationFixture(unreadCount: 7)]);

    resume();
    await pumpEventQueue();

    expect(chat.conversationsFetchCount, chatBefore + 1);
    expect(cards.fetchAcceptancesCount, cardsBefore + 1);
    // 하단 내비 뱃지가 읽는 값이 새로 바뀐다.
    expect(container.read(chatBadgeCountProvider), 7);
  });

  test('로그아웃 상태면 아무것도 읽지 않는다 — 목록 provider 도 만들지 않는다', () async {
    resume(isAuthenticated: false);
    await pumpEventQueue();

    expect(chat.conversationsFetchCount, 0);
    expect(cards.fetchAcceptancesCount, 0);
  });

  test('관문이 끝나지 않았으면 읽지 않는다 — 인증 전 계정은 대화 조회가 막힌다', () async {
    for (final gate in VerificationGate.values.where((gate) => gate != VerificationGate.complete)) {
      resume(gate: gate);
    }
    await pumpEventQueue();

    expect(chat.conversationsFetchCount, 0);
    expect(cards.fetchAcceptancesCount, 0);
  });

  test('이미 읽는 중이면 돌아와도 또 읽지 않는다', () async {
    chat.holdConversations = Completer<void>();
    resume();
    await pumpEventQueue();
    expect(chat.conversationsFetchCount, 1);

    resume();
    await pumpEventQueue();

    expect(chat.conversationsFetchCount, 1);
    chat.holdConversations!.complete();
    await pumpEventQueue();
    expect(container.read(conversationsViewModelProvider).conversations, hasLength(1));
  });

  test('돌아와 읽는 중에 푸시 갱신이 오면 그 읽기가 끝난 뒤 한 번 더 읽는다', () async {
    await warmUp();
    chat.holdConversations = Completer<void>();
    resume();
    await pumpEventQueue();
    final before = chat.conversationsFetchCount;

    // 읽는 중에 도착한 푸시는 이미 시작된 읽기가 못 본 변화를 알리는 것일 수 있다.
    refreshForPush(container.read, {'route': 'chat'});
    refreshForPush(container.read, {'route': 'chat'});
    await pumpEventQueue();
    expect(chat.conversationsFetchCount, before);
    chat.holdConversations!.complete();
    await pumpEventQueue();

    expect(chat.conversationsFetchCount, before + 1);
  });

  test('돌아와 다시 읽다 실패해도 있던 줄은 남고 오류 문구는 새로 생기지 않는다', () async {
    await warmUp();
    chat.conversations = const FailureResult(NetworkFailure());
    cards.acceptances = const FailureResult(NetworkFailure());

    resume();
    await pumpEventQueue();

    final chats = container.read(conversationsViewModelProvider);
    expect(chats.conversations, hasLength(1));
    expect(chats.errorMessage, isNull);
    expect(container.read(acceptancesViewModelProvider).errorMessage, isNull);
  });

  test('처음 읽기가 복귀와 겹쳐 실패하면 로딩을 끝내고 오류를 보인다', () async {
    chat.conversations = const FailureResult(NetworkFailure());

    resume();
    await pumpEventQueue();

    final chats = container.read(conversationsViewModelProvider);
    expect(chats.isLoading, isFalse);
    expect(chats.errorMessage, isNotNull);
  });
}
