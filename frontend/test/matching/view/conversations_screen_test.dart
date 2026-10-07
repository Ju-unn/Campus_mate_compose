import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/chat/model/message.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/matching/model/acceptance.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/matching/model/card_repository.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/view/conversations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  /// 섹션 헤더 칸(제목을 감싼 가장 가까운 Container)의 높이.
  double headerHeight(WidgetTester tester, String title) =>
      tester.getSize(find.ancestor(of: find.text(title), matching: find.byType(Container)).first).height;

  testWidgets('수락 대기 섹션에 사람 수와 행을 보여준다', (tester) async {
    final repository = FakeCardRepository()..acceptances = const Success([_acceptance]);

    await pump(tester, repository);

    expect(find.text('수락 대기'), findsOneWidget);
    expect(find.text('1명'), findsOneWidget);
    expect(find.text('초코라떼, 25'), findsOneWidget);
    expect(find.text('수락하고 대화 시작'), findsOneWidget);
  });

  for (final scale in [1.0, 1.75, 2.0]) {
    testWidgets('글자 배율 $scale 에서 섹션 헤더가 넘치거나 잘리지 않는다', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final chat = FakeChatRepository()..conversations = Success([conversationFixture()]);
      final repository = FakeCardRepository()..acceptances = const Success([_acceptance]);

      await pump(tester, repository, chat);

      // 높이 44 고정이면 제목(20 × 1.4 = 28)이 1.75 에서 49 가 되어 넘친다.
      expect(tester.takeException(), isNull);
      for (final title in ['수락 대기', '대화 중']) {
        final p = tester.renderObject<RenderParagraph>(find.text(title));
        expect(p.size.height, greaterThanOrEqualTo(p.getMaxIntrinsicHeight(p.size.width) - 0.5), reason: title);
        // 배율 1.0 에서는 pen 높이 44 그대로다.
        if (scale == 1.0) expect(headerHeight(tester, title), 44, reason: title);
      }
    });
  }

  testWidgets('목록을 내려도 수락 대기 헤더는 위에 붙어 있고 대화 중 헤더는 같이 올라간다', (tester) async {
    final chat = FakeChatRepository()
      ..conversations = Success([
        for (var i = 0; i < 15; i++) conversationFixture(matchId: 'm$i', nickname: '사람$i'),
      ]);
    final repository = FakeCardRepository()..acceptances = const Success([_acceptance]);
    await pump(tester, repository, chat);
    final top = tester.getTopLeft(find.byType(CustomScrollView)).dy;

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('수락 대기')).dy, greaterThanOrEqualTo(top));
    expect(tester.getRect(find.text('수락 대기')).top - top, lessThan(44));
    expect(find.text('대화 중').hitTestable(), findsNothing);
  });

  testWidgets('수락 대기가 0건이면 대화 중 헤더만 높이 44 로 맨 위에 온다', (tester) async {
    final chat = FakeChatRepository()..conversations = Success([conversationFixture()]);
    await pump(tester, FakeCardRepository(), chat);

    expect(find.text('수락 대기'), findsNothing);
    expect(find.text('1명'), findsOneWidget);
    expect(headerHeight(tester, '대화 중'), 44);
    expect(
      tester.getRect(find.text('대화 중')).top - tester.getTopLeft(find.byType(CustomScrollView)).dy,
      lessThan(44),
    );
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

  group('13a 밀어서 나가기(결정 10 · B7, pen zMfIn)', () {
    late FakeChatRepository chat;

    setUp(() {
      chat = FakeChatRepository()
        ..conversations = Success([
          conversationFixture(nickname: '여우비'),
          conversationFixture(matchId: 'm2', nickname: '토끼'),
        ]);
    });

    Future<void> swipeAndLeave(WidgetTester tester, String nickname) async {
      await tester.drag(find.text(nickname), const Offset(-200, 0));
      await tester.pumpAndSettle();
      // 줄마다 숨은 "나가기" 가 있다 — 밀어서 드러난 것만 누를 수 있다.
      await tester.tap(find.text('나가기').hitTestable());
      await tester.pumpAndSettle();
    }

    testWidgets('밀고 "나가기" → 확인 다이얼로그 → 나가면 저장소 leave, 그 줄이 빠진다', (tester) async {
      await pump(tester, FakeCardRepository(), chat);

      await swipeAndLeave(tester, '여우비');
      expect(find.text('채팅방을 나갈까요?'), findsOneWidget);
      expect(chat.leaveCount, 0);
      await tester.tap(find.widgetWithText(TextButton, '나가기'));
      await tester.pumpAndSettle();

      expect(chat.leaveCount, 1);
      expect(find.text('여우비'), findsNothing);
      expect(find.text('토끼'), findsOneWidget);
      expect(find.text('1명'), findsOneWidget);
    });

    testWidgets('다이얼로그에서 취소하면 아무것도 보내지 않고 줄이 남는다', (tester) async {
      await pump(tester, FakeCardRepository(), chat);

      await swipeAndLeave(tester, '여우비');
      await tester.tap(find.widgetWithText(TextButton, '취소'));
      await tester.pumpAndSettle();

      expect(chat.leaveCount, 0);
      expect(find.text('여우비'), findsOneWidget);
    });

    testWidgets('나가기가 실패하면 줄은 남고 위에 오류 문구가 뜬다', (tester) async {
      chat.writeResult = const FailureResult(NetworkFailure());
      await pump(tester, FakeCardRepository(), chat);

      await swipeAndLeave(tester, '여우비');
      await tester.tap(find.widgetWithText(TextButton, '나가기'));
      await tester.pumpAndSettle();

      expect(chat.leaveCount, 1);
      expect(find.text('여우비'), findsOneWidget);
      expect(find.text(const NetworkFailure().toDisplayMessage()), findsOneWidget);
    });

    testWidgets('이미 나간 대화(409)면 실패가 아니다 — 줄이 빠지고 오류 문구도 없다', (tester) async {
      chat.writeResult = const FailureResult(ServerRejectedFailure('이미 나간 대화예요'));
      await pump(tester, FakeCardRepository(), chat);

      await swipeAndLeave(tester, '여우비');
      await tester.tap(find.widgetWithText(TextButton, '나가기'));
      await tester.pumpAndSettle();

      expect(find.text('여우비'), findsNothing);
      expect(find.text('이미 나간 대화예요'), findsNothing);
    });
  });

  group('화면에 들어올 때마다 수락 대기와 대화 목록을 다시 읽는다', () {
    late FakeChatRepository chat;
    late FakeCardRepository cards;
    late ProviderContainer container;

    setUp(() {
      chat = FakeChatRepository()..conversations = Success([conversationFixture(unreadCount: 2)]);
      cards = FakeCardRepository();
      container = ProviderContainer(
        overrides: [
          cardRepositoryProvider.overrideWithValue(cards),
          chatRepositoryProvider.overrideWithValue(chat),
        ],
      );
      addTearDown(container.dispose);
    });

    Future<void> openScreen(WidgetTester tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ConversationsScreen()),
        ),
      );
      await tester.pump();
    }

    // 다른 탭으로 갔다가 이 화면으로 돌아오는 것과 같다 — 화면이 새로 만들어진다.
    Future<void> leaveAndReturn(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await openScreen(tester);
    }

    testWidgets('화면을 처음 열 때는 두 목록을 한 번씩만 읽는다', (tester) async {
      await openScreen(tester);

      expect(chat.conversationsFetchCount, 1);
      expect(cards.fetchAcceptancesCount, 1);
    });

    testWidgets('다른 탭에 갔다가 이 화면으로 돌아오면 대화 목록을 다시 읽는다', (tester) async {
      await openScreen(tester);
      chat.conversations = Success([conversationFixture(unreadCount: 7)]);

      await leaveAndReturn(tester);

      expect(chat.conversationsFetchCount, 2);
      expect(find.text('7'), findsWidgets);
    });

    testWidgets('다른 탭에 갔다가 이 화면으로 돌아오면 수락 대기도 다시 읽는다', (tester) async {
      await openScreen(tester);
      expect(find.text('수락 대기'), findsNothing);
      cards.acceptances = const Success([_acceptance]);

      await leaveAndReturn(tester);

      expect(cards.fetchAcceptancesCount, 2);
      expect(find.text('초코라떼, 25'), findsOneWidget);
    });

    testWidgets('돌아와 다시 읽다 실패해도 있던 줄은 남고 오류 문구는 새로 뜨지 않는다', (tester) async {
      cards.acceptances = const Success([_acceptance]);
      await openScreen(tester);
      expect(find.text('여우비'), findsOneWidget);
      chat.conversations = const FailureResult(NetworkFailure());
      cards.acceptances = const FailureResult(NetworkFailure());

      await leaveAndReturn(tester);

      expect(chat.conversationsFetchCount, 2);
      expect(find.text('여우비'), findsOneWidget);
      expect(find.text('초코라떼, 25'), findsOneWidget);
      expect(find.text(const NetworkFailure().toDisplayMessage()), findsNothing);
    });

    testWidgets('당겨서 새로고침이 실패하면 오류 문구를 보여준다', (tester) async {
      await openScreen(tester);
      chat.conversations = const FailureResult(NetworkFailure());

      await tester.fling(find.byType(CustomScrollView), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();

      expect(find.text(const NetworkFailure().toDisplayMessage()), findsOneWidget);
      expect(find.text('여우비'), findsOneWidget);
    });
  });
}
