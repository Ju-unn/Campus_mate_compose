import 'dart:async';

import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/notifications/model/app_notification.dart';
import 'package:campus_mate/notifications/model/notifications_repository_provider.dart';
import 'package:campus_mate/notifications/view/notification_row.dart';
import 'package:campus_mate/notifications/view/notifications_screen.dart';
import 'package:campus_mate/notifications/viewmodel/unread_count_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../chat/model/fake_chat_repository.dart';
import '../../matching/model/fake_card_repository.dart';
import '../model/fake_notifications_repository.dart';

/// 09c 알림함(pen `WiGM2` 목록 · `fANzR` 빈 상태 · `vGd3l` 불러오기 실패 · `QUfcS` 로딩) 값 대조.
/// 화면 360×780, 글자 배율 1.0 기준 값은 pen 노드 id 를 주석에 단다.
void main() {
  final now = DateTime(2026, 10, 10, 12);
  late FakeNotificationsRepository repo;
  late FakeChatRepository chat;
  late GoRouter router;
  late ProviderContainer container;

  /// pen 목록 `WiGM2` 7줄: 안 읽음 3 + 읽음 4.
  List<AppNotification> penRows() => [
        fakeNotification('1',
            kind: NotificationKind.cardArrived,
            title: '오늘의 카드가 도착했어요',
            body: '지금 확인해 보세요',
            data: {'route': 'daily_card'},
            createdAt: now.subtract(const Duration(seconds: 20))),
        fakeNotification('2',
            kind: NotificationKind.chatRequest,
            title: '대화 신청이 왔어요',
            body: '토끼 님이 대화를 신청했어요',
            data: {'route': 'friend_reviews'},
            createdAt: now.subtract(const Duration(hours: 1))),
        fakeNotification('3',
            kind: NotificationKind.matchMade,
            title: '매칭됐어요!',
            body: '토끼 님과 대화를 시작해 보세요',
            data: {'route': 'chat', 'match_id': 'm-9'},
            createdAt: now.subtract(const Duration(hours: 3))),
        fakeNotification('4',
            kind: NotificationKind.friendReview,
            title: '새 지인 리뷰가 도착했어요',
            body: '친구가 남긴 리뷰를 확인해 보세요',
            read: true,
            createdAt: now.subtract(const Duration(hours: 30))),
        fakeNotification('5',
            kind: NotificationKind.verificationResult,
            title: '학생증 인증이 완료됐어요',
            body: '이제 모든 기능을 쓸 수 있어요',
            read: true,
            createdAt: now.subtract(const Duration(hours: 30))),
        fakeNotification('6',
            kind: NotificationKind.nightDigest,
            title: '밤사이 2명이 대화를 신청했어요',
            body: '받은 신청에서 확인해 보세요',
            read: true,
            createdAt: now.subtract(const Duration(days: 2))),
        fakeNotification('7',
            kind: NotificationKind.cardArrived,
            title: '오늘의 카드가 도착했어요',
            body: '지금 확인해 보세요',
            read: true,
            createdAt: now.subtract(const Duration(days: 3))),
      ];

  Future<void> pump(
    WidgetTester tester, {
    FakeNotificationsRepository? repository,
    double textScale = 1.0,
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (textScale != 1.0) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    repo = repository ?? FakeNotificationsRepository(pages: [NotificationsPage(items: penRows(), unreadCount: 3)]);
    chat = FakeChatRepository();
    container = ProviderContainer(overrides: [
      notificationsRepositoryProvider.overrideWithValue(repo),
      notificationsNowProvider.overrideWithValue(() => now),
      chatRepositoryProvider.overrideWithValue(chat),
      cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
    ]);
    addTearDown(container.dispose);
    router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (context, state) => const Scaffold(body: Text('홈 화면'))),
        GoRoute(path: AppRoutes.notifications, builder: (context, state) => const NotificationsScreen()),
        GoRoute(path: AppRoutes.friendReviews, builder: (context, state) => const Scaffold(body: Text('받은 리뷰 화면'))),
        GoRoute(path: '${AppRoutes.friendReviewWrite}/:profileId', builder: (context, state) => const Scaffold(body: Text('리뷰 쓰기 시트'))),
        GoRoute(path: AppRoutes.today, builder: (context, state) => const Scaffold(body: Text('오늘 탭'))),
        GoRoute(path: AppRoutes.conversations, builder: (context, state) => const Scaffold(body: Text('대화 화면'))),
        GoRoute(path: '${AppRoutes.chatRoom}/:matchId', builder: (context, state) => Text('방 ${state.pathParameters['matchId']}')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    unawaited(router.push(AppRoutes.notifications));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  final markAll = find.text('모두 읽음');
  Finder row(String id) => find.byKey(notificationRowKey(id));
  TextStyle styleOf(WidgetTester tester, Finder f) => tester.widget<Text>(f).style!;

  group('앱바 — pen `XG5nM`(AppBar · Sub 마스터 `KH1hX`)', () {
    testWidgets('높이 56 · 제목 "알림" 18/700 · 뒤로 화살표 48×48 이 x12', (tester) async {
      await pump(tester);

      expect(tester.getSize(find.byType(AppBar)).height, 56);
      final title = find.descendant(of: find.byType(AppBar), matching: find.text('알림'));
      expect(styleOf(tester, title).fontSize, 18);
      expect(styleOf(tester, title).fontWeight, FontWeight.w700);
      expect(tester.getTopLeft(title).dx, 64); // pen `YSMvI` x64
      final back = find.descendant(of: find.byType(AppBar), matching: find.byType(IconButton));
      expect(tester.getSize(back), const Size(48, 48));
      expect(tester.getTopLeft(back).dx, 12); // pen `ftxse` x12
    });

    testWidgets('하단 내비가 없다', (tester) async {
      await pump(tester);

      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('대화'), findsNothing);
    });

    testWidgets('뒤로 화살표는 이 화면을 닫고 홈으로 돌아간다', (tester) async {
      await pump(tester);

      await tester.tap(find.byIcon(Icons.arrow_back).evaluate().isNotEmpty
          ? find.byIcon(Icons.arrow_back)
          : find.descendant(of: find.byType(AppBar), matching: find.byType(IconButton)));
      await tester.pumpAndSettle();

      expect(find.text('홈 화면'), findsOneWidget);
      expect(find.byType(NotificationsScreen), findsNothing);
    });
  });

  group('목록 — pen `WiGM2`', () {
    testWidgets('pen 7줄의 제목 · 본문 · 시간 문구가 그대로 나온다', (tester) async {
      await pump(tester);

      for (final text in [
        '오늘의 카드가 도착했어요', '지금 확인해 보세요', '방금 전',
        '대화 신청이 왔어요', '토끼 님이 대화를 신청했어요', '1시간 전',
        '매칭됐어요!', '토끼 님과 대화를 시작해 보세요', '3시간 전',
        '새 지인 리뷰가 도착했어요', '친구가 남긴 리뷰를 확인해 보세요', '어제',
        '학생증 인증이 완료됐어요', '이제 모든 기능을 쓸 수 있어요',
        '밤사이 2명이 대화를 신청했어요', '받은 신청에서 확인해 보세요', '2일 전', '3일 전',
      ]) {
        expect(find.text(text), findsWidgets, reason: text);
      }
      expect(find.byKey(const ValueKey('notification-row-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('notification-row-7')), findsOneWidget);
    });

    testWidgets('한 줄은 328 × 96(`votNn`), 목록 좌우 여백 16, 앱바 바로 아래(y56)에서 시작한다', (tester) async {
      await pump(tester);

      expect(tester.getSize(row('1')), const Size(328, 96));
      expect(tester.getTopLeft(row('1')), const Offset(16, 56));
      expect(tester.getTopLeft(row('2')), const Offset(16, 152)); // 96 뒤
      expect(tester.getSize(row('7')).height, 96); // 마지막 줄도 같은 높이(선만 끈다)
    });

    testWidgets('아이콘 원 44(`Sa6Lv`) 는 x14 · y14, 그 안 3D 그림 28(`OaDey`), 글 칸은 x70(`TQ17e`)', (tester) async {
      await pump(tester);

      final circle = find.descendant(of: row('1'), matching: find.byKey(notificationIconCircleKey));
      expect(tester.getSize(circle), const Size(44, 44));
      expect(tester.getTopLeft(circle) - tester.getTopLeft(row('1')), const Offset(14, 14));
      final decoration = tester.widget<DecoratedBox>(find.descendant(of: circle, matching: find.byType(DecoratedBox)).first).decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.color, AppColors.surfaceSoft);
      expect(tester.getSize(find.descendant(of: circle, matching: find.byType(Image))), const Size(28, 28));
      final title = find.descendant(of: row('1'), matching: find.text('오늘의 카드가 도착했어요'));
      expect(tester.getTopLeft(title).dx - tester.getTopLeft(row('1')).dx, 70);
    });

    testWidgets('글 세 줄의 크기와 간격: 제목 15/700 상자 22 · 본문 14 상자 21 · 시간 12 상자 17, 사이 4(`u7UpP` · `mjafy` · `HiHiY`)', (tester) async {
      await pump(tester);

      final title = find.descendant(of: row('1'), matching: find.text('오늘의 카드가 도착했어요'));
      final body = find.descendant(of: row('1'), matching: find.text('지금 확인해 보세요'));
      final time = find.descendant(of: row('1'), matching: find.text('방금 전'));
      expect(tester.getSize(title).height, 22);
      expect(tester.getSize(body).height, 21);
      expect(tester.getSize(time).height, 17);
      expect(tester.getTopLeft(body).dy - tester.getBottomLeft(title).dy, 4);
      expect(tester.getTopLeft(time).dy - tester.getBottomLeft(body).dy, 4);
      expect(styleOf(tester, title).fontSize, 15);
      expect(styleOf(tester, body).fontSize, 14);
      expect(styleOf(tester, time).fontSize, 12);
    });

    testWidgets('안 읽음: 제목 700 · ink, 점 8×8 primary 가 오른쪽 위(`SsMJS`, 슬롯 x306 · 위 7)', (tester) async {
      await pump(tester);

      final title = find.descendant(of: row('1'), matching: find.text('오늘의 카드가 도착했어요'));
      expect(styleOf(tester, title).fontWeight, FontWeight.w700);
      expect(styleOf(tester, title).color, AppColors.ink);
      final dot = find.descendant(of: row('1'), matching: find.byKey(notificationUnreadDotKey));
      expect(tester.getSize(dot), const Size(8, 8));
      expect(tester.getTopLeft(dot) - tester.getTopLeft(row('1')), const Offset(306, 14 + 7));
      final decoration = tester.widget<DecoratedBox>(find.descendant(of: dot, matching: find.byType(DecoratedBox)).first).decoration as BoxDecoration;
      expect(decoration.color, AppColors.primary);
      expect(decoration.shape, BoxShape.circle);
      expect(find.byKey(notificationUnreadDotKey), findsNWidgets(3));
    });

    testWidgets('읽음: 제목 400 · muted(`roXN6`), 점 없음', (tester) async {
      await pump(tester);

      final title = find.descendant(of: row('4'), matching: find.text('새 지인 리뷰가 도착했어요'));
      expect(styleOf(tester, title).fontWeight, FontWeight.w400);
      expect(styleOf(tester, title).color, AppColors.muted);
      expect(find.descendant(of: row('4'), matching: find.byKey(notificationUnreadDotKey)), findsNothing);
    });

    testWidgets('읽음 줄도 점 슬롯 폭 8 + 앞 간격 12 를 비워 둬서 글 칸이 안 읽음과 같은 224(`FOB6f` 복원 · 점 `OYASd` 만 숨김)', (tester) async {
      await pump(
        tester,
        repository: FakeNotificationsRepository(pages: [
          NotificationsPage(
            items: [
              fakeNotification('u', body: '아주 긴 본문 ' * 30),
              fakeNotification('r', body: '아주 긴 본문 ' * 30, read: true),
            ],
            unreadCount: 1,
          ),
        ]),
      );

      Finder body(String id) => find.descendant(of: row(id), matching: find.textContaining('아주 긴 본문'));
      expect(tester.getSize(body('u')).width, 224); // 안 읽음 `votNn` Copy
      expect(tester.getSize(body('r')).width, 224); // 읽음 `xmVrG` Copy (옛 244)
      expect(tester.getTopLeft(body('r')).dx, tester.getTopLeft(body('u')).dx);
      expect(find.descendant(of: row('r'), matching: find.byKey(notificationUnreadDotKey)), findsNothing);
      expect(find.descendant(of: row('u'), matching: find.byKey(notificationUnreadDotKey)), findsOneWidget);
    });

    testWidgets('본문 14 muted, 시간 12 muted(대비 4.5:1 을 넘기려 #9A9A9A 대신 muted)', (tester) async {
      await pump(tester);

      expect(styleOf(tester, find.descendant(of: row('1'), matching: find.text('지금 확인해 보세요'))).color, AppColors.muted);
      expect(styleOf(tester, find.descendant(of: row('1'), matching: find.text('방금 전'))).color, AppColors.muted);
    });

    testWidgets('본문은 최대 두 줄', (tester) async {
      await pump(
        tester,
        repository: FakeNotificationsRepository(pages: [
          NotificationsPage(items: [fakeNotification('long', body: '아주 긴 본문 ' * 30)], unreadCount: 1),
        ]),
      );

      final body = tester.widget<Text>(find.textContaining('아주 긴 본문'));
      expect(body.maxLines, 2);
      expect(body.overflow, TextOverflow.ellipsis);
    });

    testWidgets('줄 아래 선 1px hairline-soft, 마지막 줄은 선이 없다(`eu4ww` 선 #FFFFFF00)', (tester) async {
      await pump(tester);

      Border? borderOf(String id) {
        final boxes = find.descendant(of: row(id), matching: find.byType(DecoratedBox));
        for (final box in tester.widgetList<DecoratedBox>(boxes)) {
          final d = box.decoration;
          if (d is BoxDecoration && d.border is Border) return d.border as Border;
        }
        return null;
      }

      expect(borderOf('1')!.bottom.color, AppColors.hairlineSoft);
      expect(borderOf('1')!.bottom.width, 1);
      expect(borderOf('7'), isNull);
    });

    testWidgets('종류별 3D 그림: 카드 도착 layers · 대화 신청 chat · 매칭 heart · 지인 리뷰 heartHandshake · 학생증 badgeCheck · 밤사이 bell', (tester) async {
      await pump(tester);

      String assetOf(String id) {
        final image = tester.widget<Image>(find.descendant(of: row(id), matching: find.byType(Image)));
        return ((image.image) as ResizeImage).imageProvider is AssetImage
            ? (((image.image) as ResizeImage).imageProvider as AssetImage).assetName
            : '';
      }

      expect(assetOf('1'), 'assets/icons/ui-3d-layers.webp'); // wAQtn
      expect(assetOf('2'), 'assets/icons/feature-icon-chat-3d-tight.webp'); // Lua1H
      expect(assetOf('3'), 'assets/icons/ui-3d-heart.webp'); // zxXQG
      expect(assetOf('4'), 'assets/icons/ui-3d-heart-handshake.webp'); // dAIki
      expect(assetOf('5'), 'assets/icons/ui-3d-badge-check.webp'); // Trtii
      expect(assetOf('6'), 'assets/icons/ui-3d-bell.webp'); // WyOg1
    });

    testWidgets('"모두 읽음" 은 오른쪽 위, 높이 48, 14/600 primary-text(`q7PN8` · `CkuaM`), 오른쪽 끝 x348', (tester) async {
      await pump(tester);

      final label = tester.widget<Text>(markAll);
      expect(label.style!.fontSize, 14);
      expect(label.style!.fontWeight, FontWeight.w600);
      expect(label.style!.color, AppColors.primaryText);
      final button = find.ancestor(of: markAll, matching: find.byType(TextButton));
      expect(tester.getSize(button).height, 48);
      expect(tester.getTopRight(button).dx, 348);
    });

    testWidgets('안 읽은 알림이 하나도 없으면 "모두 읽음" 을 숨긴다(pen 에 없는 상태)', (tester) async {
      await pump(
        tester,
        repository: FakeNotificationsRepository(pages: [
          NotificationsPage(items: [fakeNotification('a', read: true)], unreadCount: 0),
        ]),
      );

      expect(markAll, findsNothing);
    });
  });

  group('동작', () {
    testWidgets('줄을 누르면 읽음으로 바뀌고 서버에 알리고, 푸시와 같은 규칙으로 이동한다(friend_reviews → 받은 리뷰)', (tester) async {
      await pump(
        tester,
        repository: FakeNotificationsRepository(pages: [
          NotificationsPage(
            items: [fakeNotification('a', title: '새 리뷰', data: {'route': 'friend_reviews'})],
            unreadCount: 1,
          ),
        ]),
      );

      await tester.tap(row('a'));
      await tester.pumpAndSettle();

      expect(repo.markedRead, ['a']);
      expect(container.read(unreadCountProvider), 0);
      expect(find.text('받은 리뷰 화면'), findsOneWidget);
    });

    Future<void> tapOnly(WidgetTester tester, Map<String, dynamic> data) async {
      await pump(
        tester,
        repository: FakeNotificationsRepository(pages: [
          NotificationsPage(items: [fakeNotification('a', data: data)], unreadCount: 1),
        ]),
      );
      await tester.tap(row('a'));
      await tester.pumpAndSettle();
    }

    testWidgets('오늘의 카드 · 대화 목록 알림은 탭 이동(go)이라 알림함이 닫힌다', (tester) async {
      await tapOnly(tester, {'route': 'daily_card'});
      expect(find.text('오늘 탭'), findsOneWidget);
      expect(find.byType(NotificationsScreen), findsNothing);
    });

    testWidgets('받은 신청 · 매칭 알림(대화 목록)도 go 라 알림함이 닫힌다', (tester) async {
      await tapOnly(tester, {'route': 'acceptances'});
      expect(find.text('대화 화면'), findsOneWidget);
      expect(find.byType(NotificationsScreen), findsNothing);
    });

    testWidgets('지인 리뷰 쓰기(friend_review_write)는 go 다(홈 위 시트 경로)', (tester) async {
      await pump(
        tester,
        repository: FakeNotificationsRepository(pages: [
          NotificationsPage(
            items: [fakeNotification('a', data: {'route': 'friend_review_write', 'profile_id': 'p1'})],
            unreadCount: 1,
          ),
        ]),
      );
      await tester.tap(row('a'));
      await tester.pumpAndSettle();

      expect(find.text('리뷰 쓰기 시트'), findsOneWidget);
      expect(find.byType(NotificationsScreen), findsNothing);
    });

    testWidgets('받은 리뷰 알림은 push 라 뒤로가기가 알림함으로 돌아온다', (tester) async {
      await tapOnly(tester, {'route': 'friend_reviews'});
      expect(find.text('받은 리뷰 화면'), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(find.text('받은 리뷰 화면'), findsNothing);
    });

    testWidgets('채팅방 알림도 push 라 뒤로가기가 알림함으로 돌아온다', (tester) async {
      await tapOnly(tester, {'route': 'chat', 'match_id': 'm-9'});
      expect(find.text('방 m-9'), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsScreen), findsOneWidget);
    });

    testWidgets('chat 알림은 그 방으로 간다(match_id)', (tester) async {
      await pump(
        tester,
        repository: FakeNotificationsRepository(pages: [
          NotificationsPage(
            items: [fakeNotification('a', data: {'route': 'chat', 'match_id': 'm-9'})],
            unreadCount: 1,
          ),
        ]),
      );

      await tester.tap(row('a'));
      await tester.pumpAndSettle();

      expect(find.text('방 m-9'), findsOneWidget);
      expect(chat.conversationsFetchCount, greaterThan(0)); // 푸시를 눌렀을 때처럼 대화 목록도 새로 읽는다
    });

    testWidgets('갈 곳을 모르는 알림은 읽음 처리만 하고 이 화면에 남는다', (tester) async {
      await pump(
        tester,
        repository: FakeNotificationsRepository(pages: [
          NotificationsPage(items: [fakeNotification('a', data: const {})], unreadCount: 1),
        ]),
      );

      await tester.tap(row('a'));
      await tester.pumpAndSettle();

      expect(repo.markedRead, ['a']);
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(find.byKey(notificationUnreadDotKey), findsNothing);
    });

    testWidgets('읽음 요청이 실패해도 이동은 막지 않는다', (tester) async {
      await pump(
        tester,
        repository: FakeNotificationsRepository(pages: [
          NotificationsPage(items: [fakeNotification('a', data: {'route': 'friend_reviews'})], unreadCount: 1),
        ])..failRead = true,
      );

      await tester.tap(row('a'));
      await tester.pumpAndSettle();

      expect(find.text('받은 리뷰 화면'), findsOneWidget);
    });

    testWidgets('"모두 읽음" 을 누르면 점이 모두 사라지고 버튼도 숨는다', (tester) async {
      await pump(tester);

      await tester.tap(markAll);
      await tester.pumpAndSettle();

      expect(repo.readAllCount, 1);
      expect(find.byKey(notificationUnreadDotKey), findsNothing);
      expect(markAll, findsNothing);
      expect(container.read(unreadCountProvider), 0);
    });

    testWidgets('아래로 끌어 끝에 닿으면 다음 쪽을 이어 붙인다', (tester) async {
      final first = [for (var i = 0; i < 12; i++) fakeNotification('p1-$i', createdAt: now.subtract(Duration(minutes: i)))];
      final second = [fakeNotification('p2-0', title: '둘째 쪽 알림', createdAt: now.subtract(const Duration(days: 5)))];
      await pump(
        tester,
        repository: FakeNotificationsRepository(pages: [
          NotificationsPage(items: first, unreadCount: 13, nextBefore: 'T1'),
          NotificationsPage(items: second, unreadCount: 13),
        ]),
      );
      expect(find.text('둘째 쪽 알림'), findsNothing);

      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -2000)); // 붙은 줄까지 내려 본다
      await tester.pumpAndSettle();

      expect(repo.listBefores, [null, 'T1']);
      expect(find.text('둘째 쪽 알림'), findsOneWidget);
    });

    testWidgets('당겨서 새로고침하면 첫 쪽을 다시 읽는다', (tester) async {
      await pump(tester);
      repo.pages = [
        NotificationsPage(items: [fakeNotification('new', title: '새로 온 알림')], unreadCount: 1),
      ];

      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();

      expect(find.text('새로 온 알림'), findsOneWidget);
      expect(find.text('대화 신청이 왔어요'), findsNothing);
    });
  });

  group('빈 상태 — pen `fANzR`', () {
    FakeNotificationsRepository empty() =>
        FakeNotificationsRepository(pages: [const NotificationsPage(items: [], unreadCount: 0)]);

    testWidgets('문구 · 3D 알림 아이콘 120 · "모두 읽음" 없음', (tester) async {
      await pump(tester, repository: empty());

      expect(find.text('아직 받은 알림이 없어요'), findsOneWidget);
      expect(find.text('카드가 도착하거나 대화 신청이 오면\n여기에 모여요'), findsOneWidget);
      expect(markAll, findsNothing);
      final icon = find.byKey(notificationEmptyIconKey);
      expect(tester.getSize(icon), const Size(120, 120));
      final title = tester.widget<Text>(find.text('아직 받은 알림이 없어요'));
      expect(title.style!.fontSize, 17);
      expect(title.style!.fontWeight, FontWeight.w600);
      expect(title.style!.color, AppColors.ink);
      final description = tester.widget<Text>(find.text('카드가 도착하거나 대화 신청이 오면\n여기에 모여요'));
      expect(description.style!.fontSize, 14);
      expect(description.style!.height, 1.5);
      expect(description.style!.color, AppColors.muted);
      expect(description.textAlign, TextAlign.center);
    });

    testWidgets('아이콘은 앱바 아래 120 + 안내 위 여백 48 = 화면 위에서 224 에 놓인다(`utaBV` 120 · `HM61F` padding 48)', (tester) async {
      await pump(tester, repository: empty());

      expect(tester.getTopLeft(find.byKey(notificationEmptyIconKey)).dy, 56 + 120 + 48);
      expect(tester.getCenter(find.byKey(notificationEmptyIconKey)).dx, 180);
    });
  });

  group('불러오기 실패 — pen `vGd3l`', () {
    FakeNotificationsRepository failing() =>
        FakeNotificationsRepository(pages: [NotificationsPage(items: penRows(), unreadCount: 3)])..failList = true;

    testWidgets('문구 · 아이콘 120 · 제목 20/700 · 설명 14, "모두 읽음" 없음', (tester) async {
      await pump(tester, repository: failing());

      expect(find.text('알림을 불러오지 못했어요'), findsOneWidget);
      expect(find.text('잠시 후 다시 시도해 주세요'), findsOneWidget);
      expect(markAll, findsNothing);
      expect(tester.getSize(find.byKey(notificationErrorIconKey)), const Size(120, 120));
      final title = tester.widget<Text>(find.text('알림을 불러오지 못했어요'));
      expect(title.style!.fontSize, 20);
      expect(title.style!.fontWeight, FontWeight.w700);
      expect(tester.widget<Text>(find.text('잠시 후 다시 시도해 주세요')).style!.fontSize, 14);
    });

    testWidgets('"다시 시도" 는 312×52, 본문 아래 여백 40 위(y688~740) — 인터넷 없음 화면(`NWGuf`)과 같은 패턴', (tester) async {
      await pump(tester, repository: failing());

      final retry = find.widgetWithText(ElevatedButton, '다시 시도');
      expect(tester.getSize(retry), const Size(312, 52));
      expect(tester.getTopLeft(retry), const Offset(24, 688));
      expect(tester.getBottomLeft(retry).dy, 780 - 40);
    });

    testWidgets('아이콘은 앱바 아래 위 여백 120 + 간격 20 + 안내 여백 48 = y244', (tester) async {
      await pump(tester, repository: failing());

      expect(tester.getTopLeft(find.byKey(notificationErrorIconKey)).dy, 56 + 120 + 20 + 48);
      expect(tester.getCenter(find.byKey(notificationErrorIconKey)).dx, 180);
    });

    testWidgets('"다시 시도" 를 누르면 다시 읽어 목록이 나온다', (tester) async {
      await pump(tester, repository: failing());
      repo.failList = false;

      await tester.tap(find.widgetWithText(ElevatedButton, '다시 시도'));
      await tester.pumpAndSettle();

      expect(find.text('오늘의 카드가 도착했어요'), findsWidgets);
      expect(find.text('알림을 불러오지 못했어요'), findsNothing);
    });
  });

  group('로딩 — pen `QUfcS`', () {
    testWidgets('스켈레톤 5줄(328×72, 원 44), 줄 사이 1px 선, "모두 읽음" 없음', (tester) async {
      await pump(tester, repository: FakeNotificationsRepository()..holdList = Completer<void>(), settle: false);

      final rows = find.byKey(notificationSkeletonRowKey);
      expect(rows, findsNWidgets(5));
      expect(tester.getSize(rows.first), const Size(328, 72));
      expect(tester.getTopLeft(rows.first), const Offset(16, 56));
      expect(tester.getTopLeft(rows.at(1)).dy, 56 + 72 + 1); // 줄 + 선 1
      expect(tester.getSize(find.descendant(of: rows.first, matching: find.byKey(notificationSkeletonAvatarKey))), const Size(44, 44));
      expect(markAll, findsNothing);
      expect(find.text('알림'), findsOneWidget);
    });
  });

  group('글자 확대 · 접근성', () {
    for (final scale in [1.3, 2.0]) {
      testWidgets('글자 $scale 배: 넘침 오류 없이 모든 줄이 48 이상의 누름 칸을 갖는다', (tester) async {
        await pump(tester, textScale: scale);

        expect(tester.takeException(), isNull);
        expect(find.byKey(notificationRowKey('1')), findsOneWidget);
        expect(tester.getSize(row('1')).height, greaterThanOrEqualTo(96));
        // 글자가 커져도 제목이 잘리지 않는다(줄바꿈으로 늘어난다).
        final title = tester.widget<Text>(find.descendant(of: row('1'), matching: find.text('오늘의 카드가 도착했어요')));
        expect(title.maxLines, isNull);
        final button = find.ancestor(of: markAll, matching: find.byType(TextButton));
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      });
    }

    testWidgets('글자 확대 2.0: 빈 상태가 넘치지 않는다', (tester) async {
      await pump(tester,
          repository: FakeNotificationsRepository(pages: [const NotificationsPage(items: [], unreadCount: 0)]),
          textScale: 2.0);

      expect(tester.takeException(), isNull);
      expect(find.text('아직 받은 알림이 없어요'), findsOneWidget);
    });

    testWidgets('글자 확대 2.0: 실패 화면이 넘치지 않고 "다시 시도" 가 바닥에 남는다', (tester) async {
      await pump(tester, repository: FakeNotificationsRepository()..failList = true, textScale: 2.0);

      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(ElevatedButton, '다시 시도'), findsOneWidget);
    });

    testWidgets('안 읽음은 색만이 아니라 낭독 문구("안 읽은 알림")로도 알려 준다', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);

      expect(find.bySemanticsLabel(RegExp('^안 읽은 알림, 오늘의 카드가 도착했어요')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^새 지인 리뷰가 도착했어요')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('눌림 효과는 화면이 아니라 줄이 그린다(가장 가까운 Material 이 줄 크기)', (tester) async {
      await pump(tester);

      final inkWell = find.descendant(of: row('1'), matching: find.byType(InkWell));
      final material = find.ancestor(of: inkWell, matching: find.byType(Material)).first;
      expect(tester.getSize(material), tester.getSize(inkWell));
      expect(tester.getSize(material).width, 328);
    });
  });

}
