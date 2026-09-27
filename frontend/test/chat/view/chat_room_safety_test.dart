import 'package:campus_mate/chat/model/chat_repository.dart';
import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/chat/model/message.dart';
import 'package:campus_mate/chat/view/bubble_report_menu.dart';
import 'package:campus_mate/chat/view/chat_room_screen.dart';
import 'package:campus_mate/chat/view/message_bubble.dart';
import 'package:campus_mate/chat/view/trust_reveal_bubble.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/safety/model/safety_repository_provider.dart';
import 'package:campus_mate/safety/view/report_sheet.dart';
import 'package:campus_mate/safety/viewmodel/report_ui_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../safety/model/fake_safety_repository.dart';
import '../model/fake_chat_repository.dart';

/// 조각 6 채팅방 진입점(계획서 A1·A2, pen `Lgdxu` · `I8fOcN` · `albnG`).
void main() {
  late FakeChatRepository chat;
  late FakeSafetyRepository safety;

  setUp(() {
    chat = FakeChatRepository()..room = Success(roomFixture());
    safety = FakeSafetyRepository();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(chat),
        messageStreamProvider.overrideWithValue(FakeMessageStream()),
        safetyRepositoryProvider.overrideWithValue(safety),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '${AppRoutes.chatRoom}/m1',
      routes: [
        // 토스트(SnackBar)는 Scaffold 위에 뜬다 — 실제 대화 목록 화면도 Scaffold 다.
        GoRoute(
          path: AppRoutes.conversations,
          builder: (context, state) => const Scaffold(body: Text('대화 목록')),
        ),
        GoRoute(
          path: '${AppRoutes.chatRoom}/:matchId',
          builder: (context, state) => ChatRoomScreen(matchId: state.pathParameters['matchId']!),
        ),
        GoRoute(
          path: '${AppRoutes.partnerProfile}/:profileId',
          builder: (context, state) => Text('프로필 ${state.pathParameters['profileId']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester, String row) async {
    await tester.tap(find.byIcon(AppIcons.ellipsis));
    await tester.pumpAndSettle();
    await tester.tap(find.text(row));
    await tester.pumpAndSettle();
  }

  Future<void> submitReport(WidgetTester tester) async {
    await tester.tap(find.text('광고·스팸'));
    await tester.pump();
    await tester.tap(find.text('신고하기').last);
    await tester.pumpAndSettle();
  }

  group('⋯ 신고하기', () {
    testWidgets('신고하면 대화 목록으로 가고 완료 토스트가 뜬다', (tester) async {
      await pump(tester);
      final fetchesBefore = chat.conversationsFetchCount;

      await openMenu(tester, '신고하기');
      expect(find.byType(ReportSheet), findsOneWidget);
      await submitReport(tester);

      expect(safety.reports.single.target, {'target_type': 'profile', 'target_id': partnerId});
      expect(find.text('대화 목록'), findsOneWidget);
      expect(find.text(reportedMessage), findsOneWidget);
      expect(chat.conversationsFetchCount, greaterThan(fetchesBefore));
    });

    testWidgets('하루 상한이면 토스트만 띄우고 방에 남는다', (tester) async {
      safety.reportResult = const FailureResult(RateLimitedFailure());
      await pump(tester);

      await openMenu(tester, '신고하기');
      await submitReport(tester);

      expect(find.byType(ChatRoomScreen), findsOneWidget);
      expect(find.text('오늘은 더 신고할 수 없어요'), findsOneWidget);
    });
  });

  group('⋯ 차단하기', () {
    testWidgets('14e 에서 차단하면 block 을 부르고 대화 목록으로 간다', (tester) async {
      await pump(tester);
      final fetchesBefore = chat.conversationsFetchCount;

      await openMenu(tester, '차단하기');
      expect(find.text('여우비 님을 차단할까요?'), findsOneWidget);
      await tester.tap(find.text('차단'));
      await tester.pumpAndSettle();

      expect(safety.blocked, [partnerId]);
      expect(find.text('대화 목록'), findsOneWidget);
      expect(chat.conversationsFetchCount, greaterThan(fetchesBefore));
    });

    testWidgets('14e 에서 취소하면 아무것도 하지 않는다', (tester) async {
      await pump(tester);

      await openMenu(tester, '차단하기');
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      expect(safety.blocked, isEmpty);
      expect(find.byType(ChatRoomScreen), findsOneWidget);
    });

    testWidgets('차단이 실패하면 방에 남아 오류 문구를 보여 준다', (tester) async {
      safety.blockResult = const FailureResult(NetworkFailure());
      await pump(tester);

      await openMenu(tester, '차단하기');
      await tester.tap(find.text('차단'));
      await tester.pumpAndSettle();

      expect(find.byType(ChatRoomScreen), findsOneWidget);
      expect(find.text('네트워크 연결을 확인해 주세요'), findsOneWidget);
    });
  });

  testWidgets('⋯ 채팅방 나가기는 기존 확인 다이얼로그로 간다', (tester) async {
    await pump(tester);

    await openMenu(tester, '채팅방 나가기');

    expect(find.text('채팅방을 나갈까요?'), findsOneWidget);
  });

  // 방 읽기가 실패해도 나갈 수는 있어야 한다(조각 5 main 동작). 상대를 모르니 신고 · 차단 줄은 뺀다.
  group('방을 못 읽었을 때 ⋯', () {
    setUp(() => chat.room = const FailureResult(NetworkFailure()));

    testWidgets('시트가 열리고 채팅방 나가기는 있고 신고하기 · 차단하기는 없다', (tester) async {
      await pump(tester);

      await tester.tap(find.byIcon(AppIcons.ellipsis));
      await tester.pumpAndSettle();

      expect(find.text('채팅방 나가기'), findsOneWidget);
      expect(find.text('신고하기'), findsNothing);
      expect(find.text('차단하기'), findsNothing);
    });

    testWidgets('나가기는 확인을 거쳐 저장소 leave 를 부르고 대화 목록으로 간다', (tester) async {
      await pump(tester);

      await openMenu(tester, '채팅방 나가기');
      expect(find.text('채팅방을 나갈까요?'), findsOneWidget);
      await tester.tap(find.text('나가기'));
      await tester.pumpAndSettle();

      expect(chat.leaveCount, 1);
      expect(find.text('대화 목록'), findsOneWidget);
    });
  });

  group('말풍선 롱프레스(pen I8fOcN)', () {
    setUp(() {
      chat.messages = Success(MessagePage(
        messages: [
          messageFixture(id: 'theirs', body: '안녕하세요'),
          messageFixture(id: 'mine', senderId: myId, body: '반가워요'),
          messageFixture(id: 'sys', kind: MessageKind.left, body: '여우비님이 채팅방을 나갔어요'),
        ],
        hasMore: false,
      ));
    });

    testWidgets('상대 말풍선을 길게 누르면 바로 아래 8 에 팝업이 뜬다', (tester) async {
      await pump(tester);
      final row = tester.getRect(find.widgetWithText(MessageBubble, '안녕하세요'));

      await tester.longPress(find.text('안녕하세요'));
      await tester.pumpAndSettle();

      expect(find.text('이 메시지 신고'), findsOneWidget);
      final popup = tester.getRect(find.byType(BubbleReportMenu));
      expect(popup.top, row.bottom + 8);
      expect(popup.left, row.left);
      expect(popup.size, const Size(208, 60));
      // 고른 말풍선은 막 위에 한 번 더 그려 밝게 남는다.
      expect(find.widgetWithText(MessageBubble, '안녕하세요'), findsNWidgets(2));
      // 눌림 효과는 행 안의 Material 에 그린다(COMMON §4-2).
      final ink = find.ancestor(of: find.text('이 메시지 신고'), matching: find.byType(InkWell)).first;
      expect(tester.getSize(ink), const Size(200, 52));
      final material = find.ancestor(of: ink, matching: find.byType(Material)).first;
      expect(tester.getSize(material), const Size(200, 52));
    });

    testWidgets('팝업 행은 그 메시지를 신고 대상으로 시트를 연다', (tester) async {
      await pump(tester);
      await tester.longPress(find.text('안녕하세요'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('이 메시지 신고'));
      await tester.pumpAndSettle();
      expect(find.byType(ReportSheet), findsOneWidget);
      await submitReport(tester);

      expect(safety.reports.single.target, {'target_type': 'message', 'target_id': 'theirs'});
      expect(find.text('대화 목록'), findsOneWidget);
    });

    testWidgets('바깥을 누르면 팝업이 닫힌다', (tester) async {
      await pump(tester);
      await tester.longPress(find.text('안녕하세요'));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(300, 700));
      await tester.pumpAndSettle();

      expect(find.byType(BubbleReportMenu), findsNothing);
    });

    testWidgets('내 말풍선과 시스템 줄은 길게 눌러도 팝업이 없다', (tester) async {
      await pump(tester);

      await tester.longPress(find.text('반가워요'));
      await tester.pumpAndSettle();
      expect(find.byType(BubbleReportMenu), findsNothing);

      await tester.longPress(find.text('여우비님이 채팅방을 나갔어요'));
      await tester.pumpAndSettle();
      expect(find.byType(BubbleReportMenu), findsNothing);
    });
  });

  group('14b 상대 프로필 보기(pen vmfRQ)', () {
    testWidgets('누르면 상대 프로필 경로로 간다', (tester) async {
      chat.room = Success(roomFixture(passed: true, kakaoId: 'fox_rain'));
      await pump(tester);

      await tester.tap(find.text('상대 프로필 보기'));
      await tester.pumpAndSettle();

      expect(find.text('프로필 $partnerId'), findsOneWidget);
    });

    // 보이는 버튼은 pen 296×44 그대로, 누르는 영역만 위아래 2 씩 넓혀 48 이다(DESIGN §10).
    for (final side in ['위', '아래']) {
      testWidgets('누르는 영역은 48 — 보이는 버튼 $side 1px 바깥을 눌러도 열린다', (tester) async {
        chat.room = Success(roomFixture(passed: true, kakaoId: 'fox_rain'));
        await pump(tester);
        final ink = find.ancestor(of: find.text('상대 프로필 보기'), matching: find.byType(InkWell)).first;
        final button = tester.getRect(ink);

        await tester.tapAt(Offset(button.center.dx, side == '위' ? button.top - 1 : button.bottom + 1));
        await tester.pumpAndSettle();

        expect(find.text('프로필 $partnerId'), findsOneWidget);
      });
    }

    testWidgets('보이는 버튼은 296×44, 눌림 효과는 버튼 안의 Material 에 그린다', (tester) async {
      chat.room = Success(roomFixture(passed: true, kakaoId: 'fox_rain'));
      await pump(tester);

      final ink = find.ancestor(of: find.text('상대 프로필 보기'), matching: find.byType(InkWell)).first;
      expect(tester.getSize(ink), const Size(296, 44));
      final material = find.ancestor(of: ink, matching: find.byType(Material)).first;
      expect(tester.getSize(material), const Size(296, 44));
      expect(
        find.descendant(of: find.byType(TrustRevealBubble), matching: find.byIcon(AppIcons.chevronRight)),
        findsOneWidget,
      );
    });
  });
}
