import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/chat/model/message.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/matching/model/acceptance.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/matching/model/card_repository.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/view/conversations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../chat/model/fake_chat_repository.dart';
import '../model/fake_card_repository.dart';

const _acceptance = Acceptance(
  cardId: 'card-1',
  profile: CardProfile(
    profileId: 'p1',
    nickname: '초코라떼',
    age: 25,
    university: '고려대학교',
    major: '경영학과',
  ),
);

void main() {
  Future<void> pump(WidgetTester tester, FakeCardRepository repository,
      [FakeChatRepository? chat]) async {
    final container = ProviderContainer(
      overrides: [
        cardRepositoryProvider.overrideWithValue(repository),
        // 하단 내비 뱃지가 안 읽은 메시지 수를 읽는다(§8.8).
        chatRepositoryProvider.overrideWithValue(chat ?? FakeChatRepository()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ConversationsScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('수락 대기 섹션에 사람 수와 행을 보여준다', (tester) async {
    final repository = FakeCardRepository()..acceptances = const Success([_acceptance]);

    await pump(tester, repository);

    expect(find.text('수락 대기'), findsOneWidget);
    expect(find.text('1명'), findsOneWidget);
    expect(find.text('초코라떼, 25'), findsOneWidget);
    expect(find.text('수락하고 대화 시작'), findsOneWidget);
  });

  testWidgets('받은 수락이 없으면 빈 상태 문구만 보여준다', (tester) async {
    await pump(tester, FakeCardRepository());

    expect(find.text('아직 시작된 대화가 없어요'), findsOneWidget);
    expect(find.text('수락 대기'), findsNothing);
  });

  testWidgets('거절을 누르면 거절이 서버로 간다', (tester) async {
    final repository = FakeCardRepository()..acceptances = const Success([_acceptance]);
    await pump(tester, repository);

    await tester.tap(find.text('거절'));
    await tester.pump();

    expect(repository.decisions.single.decision, CardDecision.reject);
  });

  testWidgets('대화 중 섹션에 건수와 행을 보여준다', (tester) async {
    final chat = FakeChatRepository()
      ..conversations = Success([
        conversationFixture(nickname: '여우비', unreadCount: 2),
        conversationFixture(matchId: 'm2', nickname: '토끼'),
      ]);

    await pump(tester, FakeCardRepository(), chat);

    expect(find.text('대화 중'), findsOneWidget);
    expect(find.text('2명'), findsOneWidget);
    expect(find.text('여우비'), findsOneWidget);
    expect(find.text('토끼'), findsOneWidget);
  });

  testWidgets('대화가 없으면 대화 중 섹션 자체를 그리지 않는다', (tester) async {
    // §8.6: 건수가 0이면 섹션을 그리지 않는다.
    final repository = FakeCardRepository()..acceptances = const Success([_acceptance]);

    await pump(tester, repository);

    expect(find.text('수락 대기'), findsOneWidget);
    expect(find.text('대화 중'), findsNothing);
  });

  testWidgets('상대가 나간 방도 목록에 남고 시스템 줄이 미리보기가 된다', (tester) async {
    // 결정 7: 빠지는 것은 닫힌 방과 내가 나간 방뿐이다.
    final chat = FakeChatRepository()
      ..conversations = Success([
        conversationFixture(
          lastMessage: '여우비님이 채팅방을 나갔어요',
          lastMessageKind: MessageKind.left,
        ),
      ]);

    await pump(tester, FakeCardRepository(), chat);

    expect(find.text('여우비님이 채팅방을 나갔어요'), findsOneWidget);
  });

  testWidgets('하단 내비 뱃지는 수락 대기와 안 읽은 메시지의 합이다', (tester) async {
    // DESIGN §8.8 — 의미는 "나를 기다리는 사람 수" 하나다.
    final repository = FakeCardRepository()..acceptances = const Success([_acceptance]);
    final chat = FakeChatRepository()
      ..conversations = Success([conversationFixture(unreadCount: 3)]);

    await pump(tester, repository, chat);

    expect(find.text('4'), findsOneWidget);
  });
}
