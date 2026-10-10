import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/home/model/home_repository_provider.dart';
import 'package:campus_mate/home/model/home_summary.dart';
import 'package:campus_mate/home/view/home_screen.dart';
import 'package:campus_mate/home/view/notify_icon_button.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/notifications/model/app_notification.dart';
import 'package:campus_mate/notifications/model/notifications_repository_provider.dart';
import 'package:campus_mate/notifications/view/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../chat/model/fake_chat_repository.dart';
import '../../matching/model/fake_card_repository.dart';
import '../../me/model/fake_me_repository.dart';
import '../../notifications/model/fake_notifications_repository.dart';
import '../model/fake_home_repository.dart';

/// 홈 앱바 종(pen `qxUeD` = `IconButton · Notify` `stzJJ`, 배지 `WegDg`)의 안 읽은 수 배지와 알림함 연결.
/// 배지는 2026-09-26 에 알림함이 없어 숨겼다가(count: 0 고정) 알림함이 생겨 다시 켠다.
void main() {
  const summary = HomeSummary(
    presentPeopleImages: ['assets/images/person-f1-blind-v1.png', 'assets/images/person-f4-blind-v1.png'],
    deliveredCards: 10,
    signups: 20,
    conversationsStarted: 30,
    reviewRating: 4.6,
    reviewCount: 57,
    campuses: ['가람대'],
    profileCompletionPercent: 40,
  );

  late FakeNotificationsRepository notifications;
  late GoRouter router;

  /// 홈의 모자이크 레일이 계속 흘러 pumpAndSettle 이 끝나지 않는다 — 몇 프레임만 흘린다.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> pump(WidgetTester tester, {int unread = 0, double textScale = 1.0}) async {
    tester.view.physicalSize = const Size(360, 884);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (textScale != 1.0) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    notifications = FakeNotificationsRepository(
      pages: [NotificationsPage(items: [fakeNotification('a')], unreadCount: unread)],
      unreadCount: unread,
    );
    final container = ProviderContainer(overrides: [
      homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const Success(summary))),
      meRepositoryProvider.overrideWithValue(FakeMeRepository(const FailureResult(NetworkFailure()))),
      cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
      chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
      notificationsRepositoryProvider.overrideWithValue(notifications),
    ]);
    addTearDown(container.dispose);
    router = GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        GoRoute(path: AppRoutes.home, builder: (context, state) => const HomeScreen()),
        GoRoute(path: AppRoutes.notifications, builder: (context, state) => const NotificationsScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)),
    );
    await settle(tester);
  }

  final bell = find.byType(NotifyIconButton);
  Finder badgeText() => find.descendant(of: bell, matching: find.byType(Text));

  group('배지 — pen `WegDg`', () {
    testWidgets('안 읽은 수가 0 이면 배지가 없다', (tester) async {
      await pump(tester, unread: 0);

      expect(badgeText(), findsNothing);
    });

    testWidgets('5 이면 배지에 5', (tester) async {
      await pump(tester, unread: 5);

      expect(find.descendant(of: bell, matching: find.text('5')), findsOneWidget);
    });

    testWidgets('120 이면 99+', (tester) async {
      await pump(tester, unread: 120);

      expect(find.descendant(of: bell, matching: find.text('99+')), findsOneWidget);
      expect(find.descendant(of: bell, matching: find.text('120')), findsNothing);
    });

    testWidgets('99 는 그대로 99', (tester) async {
      await pump(tester, unread: 99);

      expect(find.descendant(of: bell, matching: find.text('99')), findsOneWidget);
    });

    testWidgets('홈에 들어오면 안 읽은 수를 서버에서 읽는다', (tester) async {
      await pump(tester, unread: 2);

      expect(notifications.countCalls, 1);
    });

    testWidgets('종 칸은 48×48 이고 배지는 종 상자 기준 (12, -4) 에 놓인다(pen `WegDg`)', (tester) async {
      await pump(tester, unread: 5);

      expect(tester.getSize(bell), const Size(48, 48));
      final badge = find.descendant(of: bell, matching: find.byWidgetPredicate((w) => w is Container && w.constraints?.minWidth == 16));
      // 종 상자(24×24)는 칸 안 가운데 (x12, y12) — 배지는 거기서 (12, -4).
      final box = tester.getTopLeft(bell) + const Offset(12, 12);
      expect(tester.getTopLeft(badge) - box, const Offset(12, -4));
    });

    testWidgets('글자 확대 2.0 에서도 배지가 넘치지 않는다', (tester) async {
      await pump(tester, unread: 120, textScale: 2.0);

      expect(tester.takeException(), isNull);
      expect(find.descendant(of: bell, matching: find.text('99+')), findsOneWidget);
    });

    testWidgets('낭독 문구에 안 읽은 수가 들어간다', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, unread: 5);

      expect(find.bySemanticsLabel('알림 5개'), findsOneWidget);
      handle.dispose();
    });
  });

  group('종 → 알림함', () {
    testWidgets('종을 누르면 알림함이 열린다', (tester) async {
      await pump(tester, unread: 1);

      await tester.tap(bell);
      await settle(tester);

      expect(find.byType(NotificationsScreen), findsOneWidget);
    });

    testWidgets('알림함에서 돌아오면 안 읽은 수를 다시 읽는다', (tester) async {
      await pump(tester, unread: 3);
      await tester.tap(bell);
      await settle(tester);
      notifications.unreadCount = 0;
      notifications.pages = [const NotificationsPage(items: [], unreadCount: 0)];
      final callsBefore = notifications.countCalls;

      router.pop();
      await settle(tester);

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(notifications.countCalls, greaterThan(callsBefore));
      expect(badgeText(), findsNothing);
    });

    testWidgets('종 눌림 효과는 화면이 아니라 종 칸이 그린다(가장 가까운 Material 이 48×48)', (tester) async {
      await pump(tester);

      final inkWell = find.descendant(of: bell, matching: find.byType(InkWell));
      final material = find.ancestor(of: inkWell, matching: find.byType(Material)).first;
      expect(tester.getSize(material), const Size(48, 48));
    });
  });
}
