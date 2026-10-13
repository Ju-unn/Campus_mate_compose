import 'dart:async';
import 'dart:convert';

import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/chat/model/http_chat_repository.dart';
import 'package:campus_mate/chat/model/message.dart';
import 'package:campus_mate/chat/view/chat_list_row.dart';
import 'package:campus_mate/chat/viewmodel/conversations_view_model.dart';
import 'package:campus_mate/chat/viewmodel/user_channel.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/glass_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/core/http/http_send.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/matching/model/acceptance.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/matching/model/card_repository.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/model/sent_request.dart';
import 'package:campus_mate/matching/view/acceptance_row.dart';
import 'package:campus_mate/matching/view/conversations_screen.dart';
import 'package:campus_mate/matching/view/sent_request_row.dart';
import 'package:campus_mate/matching/viewmodel/sent_requests_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show GoTrueClient, Session;

import '../../chat/model/fake_chat_repository.dart';
import '../model/fake_card_repository.dart';

SentRequest _sent(String cardId, {SentRequestStatus status = SentRequestStatus.waiting, String? matchId}) => SentRequest(
      cardId: cardId,
      status: status,
      daysLeft: status == SentRequestStatus.waiting ? 3 : null,
      matchId: matchId,
      profile: CardProfile(nickname: '보낸$cardId', age: 24, university: '테스트대학교'),
    );

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

  group('유리 내비(pen `xtj0K`)', () {
    void penFrame(WidgetTester tester) {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 20);
      addTearDown(tester.view.reset);
    }

    testWidgets('목록은 알약 뒤로 이어지고, 끝까지 내리면 마지막 대화 줄 아래 16 에 알약', (tester) async {
      penFrame(tester);
      final chat = FakeChatRepository()
        ..conversations = Success([
          for (var i = 0; i < 15; i++) conversationFixture(matchId: 'm$i', nickname: '사람$i'),
        ]);
      await pump(tester, FakeCardRepository(), chat);
      await tester.pumpAndSettle();

      expect(tester.widget<Scaffold>(find.byType(Scaffold)).extendBody, isTrue);
      expect(tester.widget<GlassBottomNav>(find.byType(GlassBottomNav)).current, AppTab.chat);
      expect(tester.getRect(find.byType(CustomScrollView)).bottom, 780);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -5000));
      await tester.pumpAndSettle();

      expect(tester.getRect(find.byType(GlassBottomNav)).top - tester.getBottomLeft(find.byType(ChatListRow).last).dy, 16);
    });

    testWidgets('빈 상태는 앱바 아래 ~ 알약 위 사이 가운데에 선다', (tester) async {
      penFrame(tester);
      await pump(tester, FakeCardRepository());
      await tester.pumpAndSettle();

      final empty = find.ancestor(of: find.text('아직 시작된 대화가 없어요'), matching: find.byType(Center)).first;
      final pillTop = tester.getRect(find.byType(GlassBottomNav)).top;
      expect(tester.getCenter(empty).dy, closeTo((56 + pillTop) / 2, 0.5));
    });
  });

  testWidgets('받은 신청 섹션에 사람 수와 행을 보여준다', (tester) async {
    final repository = FakeCardRepository()..acceptances = const Success([_acceptance]);

    await pump(tester, repository);

    expect(find.text('받은 신청'), findsOneWidget);
    expect(find.text('1명'), findsOneWidget);
    expect(find.text('초코라떼, 25'), findsOneWidget);
    expect(find.text('수락하기'), findsOneWidget);
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
      for (final title in ['받은 신청', '대화 중']) {
        final p = tester.renderObject<RenderParagraph>(find.text(title));
        expect(p.size.height, greaterThanOrEqualTo(p.getMaxIntrinsicHeight(p.size.width) - 0.5), reason: title);
        // 배율 1.0 에서는 pen 높이 44 그대로다.
        if (scale == 1.0) expect(headerHeight(tester, title), 44, reason: title);
      }
    });
  }

  testWidgets('목록을 내려도 받은 신청 헤더는 위에 붙어 있고 대화 중 헤더는 같이 올라간다', (tester) async {
    final chat = FakeChatRepository()
      ..conversations = Success([
        for (var i = 0; i < 15; i++) conversationFixture(matchId: 'm$i', nickname: '사람$i'),
      ]);
    final repository = FakeCardRepository()..acceptances = const Success([_acceptance]);
    await pump(tester, repository, chat);
    final top = tester.getTopLeft(find.byType(CustomScrollView)).dy;

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('받은 신청')).dy, greaterThanOrEqualTo(top));
    expect(tester.getRect(find.text('받은 신청')).top - top, lessThan(44));
    expect(find.text('대화 중').hitTestable(), findsNothing);
  });

  testWidgets('받은 신청이 0건이면 대화 중 헤더만 높이 44 로 맨 위에 온다', (tester) async {
    final chat = FakeChatRepository()..conversations = Success([conversationFixture()]);
    await pump(tester, FakeCardRepository(), chat);

    expect(find.text('받은 신청'), findsNothing);
    expect(find.text('1명'), findsOneWidget);
    expect(headerHeight(tester, '대화 중'), 44);
    expect(
      tester.getRect(find.text('대화 중')).top - tester.getTopLeft(find.byType(CustomScrollView)).dy,
      lessThan(44),
    );
  });

  testWidgets('받은 신청이 없으면 빈 상태 문구만 보여준다', (tester) async {
    await pump(tester, FakeCardRepository());

    expect(find.text('아직 시작된 대화가 없어요'), findsOneWidget);
    // pen `X0Hha9` — 제목은 그대로, 본문만 "신청을 수락하면" 으로 바뀌었다(지시문 23 F).
    expect(find.text('신청을 수락하면 여기에서 대화를 시작할 수 있어요.'), findsOneWidget);
    expect(find.text('서로 수락하면 여기에서 대화를 시작할 수 있어요.'), findsNothing);
    expect(find.text('받은 신청'), findsNothing);
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

    expect(find.text('받은 신청'), findsOneWidget);
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

  group('보낸 신청(2026-10-13 사용자 결정 B · pen ULllO · wOZst)', () {
    /// 섹션 헤더 칸의 위끝.
    double headerTop(WidgetTester tester, String title) =>
        tester.getTopLeft(find.ancestor(of: find.text(title), matching: find.byType(Container)).first).dy;

    double headerBottom(WidgetTester tester, String title) =>
        tester.getBottomLeft(find.ancestor(of: find.text(title), matching: find.byType(Container)).first).dy;

    testWidgets('받은 신청 아래 · 대화 중 위에 "보낸 신청 N명" 섹션이 온다', (tester) async {
      final chat = FakeChatRepository()..conversations = Success([conversationFixture()]);
      final repository = FakeCardRepository()
        ..acceptances = const Success([_acceptance])
        ..sent = Success([_sent('s1'), _sent('s2', status: SentRequestStatus.rejected)]);

      await pump(tester, repository, chat);

      expect(find.text('보낸 신청'), findsOneWidget);
      expect(find.byType(SentRequestRow), findsNWidgets(2));
      final countOfSent =
          find.descendant(of: find.ancestor(of: find.text('보낸 신청'), matching: find.byType(Row)).first, matching: find.text('2명'));
      expect(countOfSent, findsOneWidget);
      expect(headerTop(tester, '받은 신청'), lessThan(headerTop(tester, '보낸 신청')));
      expect(headerTop(tester, '보낸 신청'), lessThan(headerTop(tester, '대화 중')));
      // 배율 1.0 에서 헤더는 다른 섹션과 같은 44 다.
      expect(headerHeight(tester, '보낸 신청'), 44);
    });

    testWidgets('간격: 받은 신청 끝 → 보낸 신청 헤더 22, 헤더 → 첫 행 4, 보낸 신청 끝 → 대화 중 헤더 22', (tester) async {
      final chat = FakeChatRepository()..conversations = Success([conversationFixture()]);
      final repository = FakeCardRepository()
        ..acceptances = const Success([_acceptance])
        ..sent = Success([_sent('s1'), _sent('s2')]);

      await pump(tester, repository, chat);

      final rows = find.byType(SentRequestRow);
      expect(headerTop(tester, '보낸 신청') - tester.getBottomLeft(find.byType(AcceptanceRow)).dy, 22);
      expect(tester.getTopLeft(rows.first).dy - headerBottom(tester, '보낸 신청'), 4);
      expect(headerTop(tester, '대화 중') - tester.getBottomLeft(rows.last).dy, 22);
    });

    testWidgets('행은 본문 여백 16 안에 있고 사이에 hairline-soft 1px 선이 있다', (tester) async {
      final repository = FakeCardRepository()..sent = Success([_sent('s1'), _sent('s2')]);

      await pump(tester, repository);

      final rows = find.byType(SentRequestRow);
      expect(tester.getTopLeft(rows.first).dx, 16);
      expect(tester.getTopRight(rows.first).dx, 800 - 16);
      final divider = tester.widget<Divider>(
          find.descendant(of: find.byType(SliverPadding), matching: find.byType(Divider)).first);
      expect(divider.thickness, 1);
      expect(divider.height, 1);
      expect(divider.color, AppColors.hairlineSoft);
      expect(tester.getTopLeft(rows.last).dy - tester.getBottomLeft(rows.first).dy, 1);
    });

    testWidgets('보낸 신청만 있으면 빈 화면이 아니라 보낸 신청 섹션만 맨 위에 보인다(wOZst)', (tester) async {
      final repository = FakeCardRepository()..sent = Success([_sent('s1')]);

      await pump(tester, repository);

      expect(find.text('아직 시작된 대화가 없어요'), findsNothing);
      expect(find.text('받은 신청'), findsNothing);
      expect(find.text('대화 중'), findsNothing);
      expect(find.byType(SentRequestRow), findsOneWidget);
      expect(headerTop(tester, '보낸 신청') - tester.getTopLeft(find.byType(CustomScrollView)).dy, 0);
    });

    testWidgets('셋 다 비었을 때만 빈 화면이다', (tester) async {
      await pump(tester, FakeCardRepository());

      expect(find.text('아직 시작된 대화가 없어요'), findsOneWidget);
      expect(find.text('보낸 신청'), findsNothing);
    });

    testWidgets('보낸 신청을 읽는 중이면 다른 둘이 끝났어도 스켈레톤이다 — 섹션이 뒤늦게 끼어들지 않게', (tester) async {
      final chat = FakeChatRepository()..conversations = Success([conversationFixture()]);
      final repository = FakeCardRepository()
        ..sent = Success([_sent('s1')])
        ..holdSent = Completer<void>();

      await pump(tester, repository, chat);
      expect(find.text('대화 중'), findsNothing);
      expect(find.byType(SentRequestRow), findsNothing);

      repository.holdSent!.complete();
      await tester.pump();
      await tester.pump();

      expect(find.byType(SentRequestRow), findsOneWidget);
      expect(find.text('대화 중'), findsOneWidget);
    });

    testWidgets('보낸 신청 읽기가 실패하면 위에 오류 줄이 뜨고 다른 섹션은 그대로 보인다', (tester) async {
      final chat = FakeChatRepository()..conversations = Success([conversationFixture()]);
      final repository = FakeCardRepository()
        ..acceptances = const Success([_acceptance])
        ..sent = const FailureResult(NetworkFailure());

      await pump(tester, repository, chat);

      expect(find.text(const NetworkFailure().toDisplayMessage()), findsOneWidget);
      expect(find.text('보낸 신청'), findsNothing);
      expect(find.byType(AcceptanceRow), findsOneWidget);
      expect(find.byType(ChatListRow), findsOneWidget);
    });

    testWidgets('목록을 내리면 받은 신청 헤더만 붙어 있고 보낸 신청 헤더는 같이 올라간다', (tester) async {
      final chat = FakeChatRepository()
        ..conversations = Success([
          for (var i = 0; i < 15; i++) conversationFixture(matchId: 'm$i', nickname: '사람$i'),
        ]);
      final repository = FakeCardRepository()
        ..acceptances = const Success([_acceptance])
        ..sent = Success([_sent('s1')]);
      await pump(tester, repository, chat);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(find.text('받은 신청').hitTestable(), findsOneWidget);
      expect(find.text('보낸 신청').hitTestable(), findsNothing);
    });

    testWidgets('하단 내비 숫자에 보낸 신청은 들어가지 않는다', (tester) async {
      final repository = FakeCardRepository()
        ..acceptances = const Success([_acceptance])
        ..sent = Success([_sent('s1'), _sent('s2'), _sent('s3')]);
      final chat = FakeChatRepository()..conversations = Success([conversationFixture(unreadCount: 3)]);

      await pump(tester, repository, chat);

      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('매칭됐고 방이 있는 줄을 누르면 대화 중 행과 같은 방 경로로 간다', (tester) async {
      final repository = FakeCardRepository()
        ..sent = Success([_sent('s1', status: SentRequestStatus.matched, matchId: 'm-9')]);
      final container = ProviderContainer(overrides: [
        cardRepositoryProvider.overrideWithValue(repository),
        chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
      ]);
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: AppRoutes.conversations,
        routes: [
          GoRoute(path: AppRoutes.conversations, builder: (context, state) => const ConversationsScreen()),
          GoRoute(
            path: '${AppRoutes.chatRoom}/:matchId',
            builder: (context, state) => Text('방 ${state.pathParameters['matchId']}'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(SentRequestRow));
      await tester.pumpAndSettle();

      expect(find.text('방 m-9'), findsOneWidget);
    });

    testWidgets('화면에 들어올 때 · 당겨서 새로고침할 때 보낸 신청도 다시 읽는다', (tester) async {
      final chat = FakeChatRepository()..conversations = Success([conversationFixture()]);
      final repository = FakeCardRepository();
      await pump(tester, repository, chat);
      expect(repository.fetchSentCount, 1);

      await tester.fling(find.byType(CustomScrollView), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();

      expect(repository.fetchSentCount, 2);
    });

    group('10b 에서 대화 신청하고 넘어왔을 때(Q1322I)', () {
      Future<ProviderContainer> arrive(WidgetTester tester, FakeCardRepository repository, FakeChatRepository chat) async {
        final container = ProviderContainer(overrides: [
          cardRepositoryProvider.overrideWithValue(repository),
          chatRepositoryProvider.overrideWithValue(chat),
        ]);
        addTearDown(container.dispose);
        unawaited(container.read(sentRequestsViewModelProvider.notifier).announceSent());
        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ConversationsScreen()),
        ));
        await tester.pump();
        await tester.pump();
        return container;
      }

      testWidgets('토스트 "신청을 보냈어요" 가 체크 16 과 함께 하단 내비 위 16 · 가로 가운데에 뜬다', (tester) async {
        await arrive(tester, FakeCardRepository()..sent = Success([_sent('s1')]), FakeChatRepository());
        await tester.pump(const Duration(milliseconds: 300));

        final toast = find.byType(AppToast);
        expect(toast, findsOneWidget);
        expect(tester.widget<AppToast>(toast).label, '신청을 보냈어요');
        final icon = tester.widget<Icon>(find.descendant(of: toast, matching: find.byType(Icon)));
        expect(icon.icon, AppIcons.check);
        expect(icon.size, 16);
        expect(tester.getBottomLeft(toast).dy, tester.getTopLeft(find.byType(GlassBottomNav)).dy - 16);
        expect(tester.getCenter(toast).dx, 400);
      });

      testWidgets('보낸 신청 헤더가 받은 신청 고정 헤더 바로 아래에 오도록 내려 준다', (tester) async {
        final chat = FakeChatRepository()
          ..conversations = Success([
            for (var i = 0; i < 15; i++) conversationFixture(matchId: 'm$i', nickname: '사람$i'),
          ]);
        final repository = FakeCardRepository()
          ..acceptances = Success([
            for (var i = 0; i < 4; i++)
              Acceptance(cardId: 'a$i', profile: CardProfile(profileId: 'p$i', nickname: '사람a$i', age: 25)),
          ])
          ..sent = Success([_sent('s1')]);

        await arrive(tester, repository, chat);
        await tester.pump();

        expect(headerTop(tester, '보낸 신청'), headerBottom(tester, '받은 신청'));
        expect(find.text('보낸 신청').hitTestable(), findsOneWidget);
      });

      testWidgets('그냥 탭으로 들어오면 토스트도 스크롤도 없다', (tester) async {
        final repository = FakeCardRepository()..sent = Success([_sent('s1')]);

        await pump(tester, repository);
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(AppToast), findsNothing);
      });
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
      expect(find.text('받은 신청'), findsNothing);
      cards.acceptances = const Success([_acceptance]);

      await leaveAndReturn(tester);

      expect(cards.fetchAcceptancesCount, 2);
      expect(find.text('초코라떼, 25'), findsOneWidget);
    });

    testWidgets('다른 탭에 갔다가 이 화면으로 돌아오면 보낸 신청도 다시 읽는다', (tester) async {
      await openScreen(tester);
      cards.sent = Success([_sent('s1', status: SentRequestStatus.matched, matchId: 'm-1')]);

      await leaveAndReturn(tester);

      expect(cards.fetchSentCount, 2);
      expect(find.text('매칭됨'), findsOneWidget);
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

  // 목록은 실시간 구독을 쓰지 않으니, 푸시가 없는 사이(방에서 나온 뒤 30초 등)의 새 메시지는 폴링으로 맞춘다.
  group('대화 탭이 떠 있는 동안 3초마다 대화 목록을 조용히 다시 읽는다', () {
    late FakeChatRepository chat;
    late FakeCardRepository cards;
    late ProviderContainer container;
    final navigatorKey = GlobalKey<NavigatorState>();

    setUp(() {
      chat = FakeChatRepository()..conversations = Success([conversationFixture(unreadCount: 2)]);
      cards = FakeCardRepository();
      container = ProviderContainer(
        overrides: [
          cardRepositoryProvider.overrideWithValue(cards),
          chatRepositoryProvider.overrideWithValue(chat),
          // 기본은 사용자 채널이 안 붙은 상태(정책 적용 전 · 끊김) — 지금처럼 3초다.
          userChannelProvider.overrideWith(FakeUserChannel.new),
        ],
      );
      addTearDown(container.dispose);
    });

    void setChannelLive(bool live) => (container.read(userChannelProvider.notifier) as FakeUserChannel).setLive(live);

    Future<void> openScreen(WidgetTester tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(navigatorKey: navigatorKey, home: const ConversationsScreen()),
        ),
      );
      await tester.pump();
    }

    void background(WidgetTester tester) {
      for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
    }

    void foreground(WidgetTester tester) {
      for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
    }

    testWidgets('간격은 3초 하나다(사용자 요청 10-13, 5초 → 3초)', (tester) async {
      expect(conversationsPollFast, const Duration(seconds: 3));
      expect(conversationsPollSlow, const Duration(seconds: 30));
    });

    // 사용자 채널(설계안 A)이 실제로 붙었을 때만 느리게 — 정책 적용 전(입장 거부)에는 지금처럼 3초다.
    testWidgets('사용자 채널이 붙어 있으면 30초마다만 읽는다', (tester) async {
      setChannelLive(true);
      await openScreen(tester);
      expect(chat.conversationsFetchCount, 1);

      await tester.pump(conversationsPollSlow - const Duration(milliseconds: 1));
      expect(chat.conversationsFetchCount, 1);
      await tester.pump(const Duration(milliseconds: 1));

      expect(chat.conversationsFetchCount, 2);
    });

    testWidgets('보는 중에 채널이 붙으면 30초로, 끊기면 다시 3초로 바꾼다', (tester) async {
      await openScreen(tester);

      setChannelLive(true);
      await tester.pump(conversationsPollFast * 3);
      expect(chat.conversationsFetchCount, 1, reason: '붙은 뒤에는 3초마다 읽지 않는다');

      setChannelLive(false);
      await tester.pump(conversationsPollFast);
      expect(chat.conversationsFetchCount, 2, reason: '끊기면 3초 안전망으로 돌아온다');
    });

    testWidgets('3초가 되기 전에는 다시 읽지 않고, 3초마다 한 번씩 읽는다', (tester) async {
      await openScreen(tester);
      expect(chat.conversationsFetchCount, 1);

      await tester.pump(conversationsPollFast - const Duration(milliseconds: 1));
      expect(chat.conversationsFetchCount, 1);

      await tester.pump(const Duration(milliseconds: 1));
      expect(chat.conversationsFetchCount, 2);

      await tester.pump(conversationsPollFast);
      expect(chat.conversationsFetchCount, 3);
    });

    testWidgets('푸시 없이도 새 메시지와 안 읽은 수가 목록과 하단 내비 숫자에 바뀐다', (tester) async {
      await openScreen(tester);
      expect(find.text('내일 시간 괜찮으세요?'), findsOneWidget);
      chat.conversations = Success([
        conversationFixture(lastMessage: '답장 왔어요', unreadCount: 5),
        conversationFixture(matchId: 'm2', nickname: '새방', unreadCount: 1),
      ]);

      await tester.pump(conversationsPollFast);
      await tester.pump();

      expect(find.text('답장 왔어요'), findsOneWidget);
      expect(find.text('새방'), findsOneWidget);
      expect(container.read(chatBadgeCountProvider), 6);
    });

    testWidgets('읽는 동안에도 스켈레톤 없이 있던 줄이 그대로 보인다', (tester) async {
      await openScreen(tester);
      chat.holdConversations = Completer<void>();

      await tester.pump(conversationsPollFast);

      expect(chat.conversationsFetchCount, 2);
      expect(find.text('여우비'), findsOneWidget);
      chat.holdConversations!.complete();
      await tester.pump();
    });

    testWidgets('읽는 중에 3초가 또 지나도 겹쳐 부르지 않고, 끝난 뒤 다음 주기에 읽는다', (tester) async {
      await openScreen(tester);
      chat.holdConversations = Completer<void>();

      await tester.pump(conversationsPollFast * 3);
      expect(chat.conversationsFetchCount, 2);

      chat.holdConversations!.complete();
      chat.holdConversations = null;
      await tester.pump();
      await tester.pump(conversationsPollFast);
      expect(chat.conversationsFetchCount, 3);
    });

    testWidgets('읽기가 실패해도 있던 줄은 남고 오류 문구는 없으며, 다음 주기에 다시 읽어 되살아난다', (tester) async {
      await openScreen(tester);
      chat.conversations = const FailureResult(NetworkFailure());

      await tester.pump(conversationsPollFast);
      await tester.pump();

      expect(chat.conversationsFetchCount, 2);
      expect(find.text('여우비'), findsOneWidget);
      expect(find.text(const NetworkFailure().toDisplayMessage()), findsNothing);

      chat.conversations = Success([conversationFixture(lastMessage: '다시 연결됐어요')]);
      await tester.pump(conversationsPollFast);
      await tester.pump();

      expect(chat.conversationsFetchCount, 3);
      expect(find.text('다시 연결됐어요'), findsOneWidget);
    });

    testWidgets('앱이 백그라운드에 있는 동안은 읽지 않고, 돌아오면 다시 3초마다 읽는다', (tester) async {
      await openScreen(tester);

      background(tester);
      await tester.pump(conversationsPollFast * 6);
      expect(chat.conversationsFetchCount, 1);

      foreground(tester);
      await tester.pump(conversationsPollFast);
      expect(chat.conversationsFetchCount, 2);
    });

    // iOS 순서: 알림을 눌러 켜면 화면이 inactive 인 채로 만들어지고, 알림 센터 · 제어 센터를 내리면 inactive ↔ resumed 만 오간다.
    testWidgets('inactive 로 만들어져 뒤늦게 resumed 가 와도, inactive ↔ resumed 를 여러 번 오가도 마지막 resumed 뒤 한 주기에 읽는다',
        (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await openScreen(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var i = 0; i < 3; i++) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await tester.pump(const Duration(milliseconds: 500));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      }
      final before = chat.conversationsFetchCount;

      await tester.pump(conversationsPollFast);
      expect(chat.conversationsFetchCount, before + 1);
    });

    testWidgets('다른 화면이 위에 덮이면(상세 · 채팅방) 읽지 않고, 닫히면 다시 읽는다', (tester) async {
      await openScreen(tester);

      unawaited(navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Text('방'))));
      await tester.pumpAndSettle();
      final before = chat.conversationsFetchCount;
      await tester.pump(conversationsPollFast * 6);
      expect(chat.conversationsFetchCount, before);

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      await tester.pump(conversationsPollFast);
      expect(chat.conversationsFetchCount, before + 1);
    });

    testWidgets('화면을 떠나면 타이머가 접혀 더 읽지 않는다', (tester) async {
      await openScreen(tester);

      await tester.pumpWidget(const SizedBox.shrink());
      final before = chat.conversationsFetchCount;
      await tester.pump(conversationsPollFast * 6);

      expect(chat.conversationsFetchCount, before);
    });

    // 위 시험들은 MaterialApp(home:) 위라 실제 앱의 길(셸 없는 최상위 탭 경로를 유리 내비가 `context.go` 로 바꾸고,
    // 방은 그 위에 `context.push`)을 지나지 않았다 — 그 길에서 맨 위 판정(ModalRoute.isCurrentOf)이 어긋나도 못 잡는다.
    testWidgets('실제 앱처럼 유리 내비로 탭을 옮기고 방을 열고 닫아도, 대화 탭이 맨 위일 때만 읽는다', (tester) async {
      final router = GoRouter(
        initialLocation: AppRoutes.home,
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (_, _) => const Scaffold(bottomNavigationBar: GlassBottomNav(current: AppTab.main)),
          ),
          GoRoute(path: AppRoutes.conversations, builder: (_, _) => const ConversationsScreen()),
          GoRoute(path: '${AppRoutes.chatRoom}/:matchId', builder: (_, _) => const Scaffold(body: Text('방'))),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('대화'));
      await tester.pumpAndSettle();
      final entered = chat.conversationsFetchCount;
      await tester.pump(conversationsPollFast * 2);
      expect(chat.conversationsFetchCount, entered + 2, reason: '탭에 들어와 있는 동안');

      await tester.tap(find.text('여우비'));
      await tester.pumpAndSettle();
      final inRoom = chat.conversationsFetchCount;
      await tester.pump(conversationsPollFast * 3);
      expect(chat.conversationsFetchCount, inRoom, reason: '방이 덮은 동안');

      router.pop();
      await tester.pumpAndSettle();
      final back = chat.conversationsFetchCount;
      await tester.pump(conversationsPollFast * 2);
      expect(chat.conversationsFetchCount, back + 2, reason: '방을 닫고 돌아온 뒤');

      await tester.tap(find.text('메인'));
      await tester.pumpAndSettle();
      final left = chat.conversationsFetchCount;
      await tester.pump(conversationsPollFast * 3);
      expect(chat.conversationsFetchCount, left, reason: '다른 탭으로 옮긴 뒤');
    }, variant: const TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}));
  });

  // 10-13 아이폰(Cloud Run 로그): 와이파이 → LTE 로 바뀌던 중 나간 목록 요청 하나가 끝내 안 돌아오자, 그 뒤의 폴링 · 복귀 ·
  // 방 진입 목록 읽기가 모두 읽는 중 합치기(_inFlight)로 그 요청에 묶여 앱을 껐다 켤 때까지 목록이 멈췄다.
  // 가짜 저장소는 요청이 걸리는 일이 없어 이걸 못 본다 — 실제 HTTP 저장소 · ApiClient 를 지나게 한다.
  testWidgets('목록 요청 하나가 끝내 안 돌아와도, 시간 제한 뒤 다음 주기에 다시 읽는다', (tester) async {
    var listCalls = 0;
    final client = MockClient((request) {
      listCalls += 1;
      // 첫 폴링(두 번째 읽기)만 영영 응답이 없다.
      if (listCalls == 2) return Completer<http.Response>().future;
      return Future.value(http.Response(jsonEncode({'conversations': <Object>[]}), 200));
    });
    final auth = _MockGoTrueClient();
    final session = _MockSession();
    when(() => session.accessToken).thenReturn('token');
    when(() => auth.currentSession).thenReturn(session);
    final container = ProviderContainer(overrides: [
      cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
      chatRepositoryProvider.overrideWithValue(HttpChatRepository(ApiClient('https://api.test', client, auth))),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MaterialApp(home: ConversationsScreen())),
    );
    await tester.pump();
    expect(listCalls, 1);

    await tester.pump(conversationsPollFast);
    expect(listCalls, 2, reason: '이 요청이 걸린다');

    await tester.pump(readTimeout + conversationsPollFast);
    expect(listCalls, greaterThanOrEqualTo(3), reason: '걸린 요청이 끊긴 뒤 다음 주기');
  });
}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _MockSession extends Mock implements Session {}
