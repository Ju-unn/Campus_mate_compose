import 'dart:async';

import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/consent/model/open_url.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/home/model/home_repository_provider.dart';
import 'package:campus_mate/home/model/home_summary.dart';
import 'package:campus_mate/home/model/store_review_url.dart';
import 'package:campus_mate/home/view/home_grid.dart';
import 'package:campus_mate/home/view/home_screen.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/notifications/model/notifications_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../chat/model/fake_chat_repository.dart';
import '../../matching/model/fake_card_repository.dart';
import '../../me/model/fake_me_repository.dart';
import '../model/fake_home_repository.dart';
import '../../notifications/model/fake_notifications_repository.dart';

/// 홈의 누를 곳 — "리뷰 남기기"(스토어 주소가 비어 있는 동안은 "곧 열려요"), 6칸 그리드의 인스타 · 이벤트 칸(10-15),
/// 프로필 완성도 카드(→ 프로필 편집 허브).
void main() {
  const summary = HomeSummary(
    deliveredCards: 10,
    signups: 20,
    conversationsStarted: 30,
    reviewRating: 4.6,
    reviewCount: 57,
    campuses: ['가람대'],
    profileCompletionPercent: 40,
  );

  late FakeHomeRepository home;

  /// 리뷰 남기기의 "곧 열려요" 안내 — 6칸 그리드 자리표시 칸(10-15)도 같은 글이라 토스트 안에서만 찾는다.
  Finder comingSoonToast() => find.descendant(of: find.byType(AppToast), matching: find.text('곧 열려요'));

  /// 홈을 띄우고 openUrlProvider 가 받은 주소들을 돌려준다. [opens] 는 그 호출이 돌려줄 값, [throws] 면 예외.
  Future<List<Uri>> pump(
    WidgetTester tester, {
    String storeUrl = '',
    bool opens = true,
    bool throws = false,
    Future<bool> Function(Uri)? open,
  }) async {
    tester.view.physicalSize = const Size(360, 884); // pen 프레임 — 리뷰 띠 · 카드가 화면 안에 든다
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final opened = <Uri>[];
    home = FakeHomeRepository(const Success(summary));
    final container = ProviderContainer(
      overrides: [
        homeRepositoryProvider.overrideWithValue(home),
        notificationsRepositoryProvider.overrideWithValue(FakeNotificationsRepository()),
        meRepositoryProvider.overrideWithValue(FakeMeRepository(const FailureResult(NetworkFailure()))),
        cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
        chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
        storeReviewUrlProvider.overrideWithValue(storeUrl),
        openUrlProvider.overrideWithValue(
          open ??
              (uri) async {
                opened.add(uri);
                if (throws) throw StateError('기기 쪽 오류');
                return opens;
              },
        ),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        GoRoute(path: AppRoutes.home, builder: (context, state) => const HomeScreen()),
        GoRoute(path: AppRoutes.myProfileManage, builder: (context, state) => const Text('프로필 편집 허브')),
        GoRoute(path: AppRoutes.events, builder: (context, state) => const Text('이벤트 화면')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pump();
    return opened;
  }

  /// 6칸 그리드(10-15)가 들어와 884 화면에서 리뷰 띠가 유리 내비에 걸린다 — 띠가 알약 위로 오게 올린다.
  Future<void> bringReviewUp(WidgetTester tester) async {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
    await tester.pump(const Duration(seconds: 1));
  }

  group('리뷰 남기기', () {
    testWidgets('스토어 주소가 비어 있으면 어디도 안 열고 "곧 열려요" 를 잠깐 보여 준다', (tester) async {
      final opened = await pump(tester);
      await bringReviewUp(tester);
      expect(comingSoonToast(), findsNothing);

      await tester.tap(find.text('리뷰 남기기'));
      await tester.pump();

      expect(comingSoonToast(), findsOneWidget);
      expect(opened, isEmpty);
      await tester.pump(const Duration(seconds: 2));
      expect(comingSoonToast(), findsNothing); // 약 2초 뒤 사라진다(나 탭 안내와 같다)
    });

    testWidgets('주소가 채워져 있으면 그 주소를 열고 안내는 띄우지 않는다', (tester) async {
      final opened = await pump(tester, storeUrl: 'https://play.example.test/store/apps/details?id=app');
      await bringReviewUp(tester);

      await tester.tap(find.text('리뷰 남기기'));
      await tester.pump();

      expect(opened, [Uri.parse('https://play.example.test/store/apps/details?id=app')]);
      expect(comingSoonToast(), findsNothing);
    });

    testWidgets('주소가 http(s) 가 아니면 열지 않고 "곧 열려요"', (tester) async {
      final opened = await pump(tester, storeUrl: 'not a url');
      await bringReviewUp(tester);

      await tester.tap(find.text('리뷰 남기기'));
      await tester.pump();

      expect(opened, isEmpty);
      expect(comingSoonToast(), findsOneWidget);
    });

    testWidgets('열기가 false 를 돌려주면 조용히 끝내지 않고 실패 안내를 보여 준다', (tester) async {
      final opened = await pump(tester, storeUrl: 'https://play.example.test/x', opens: false);
      await bringReviewUp(tester);

      await tester.tap(find.text('리뷰 남기기'));
      await tester.pump();

      expect(opened, hasLength(1));
      expect(find.text(const UnknownFailure().toDisplayMessage()), findsOneWidget);
      expect(comingSoonToast(), findsNothing);
    });

    testWidgets('열기가 예외를 던져도 실패 안내를 보여 준다', (tester) async {
      final opened = await pump(tester, storeUrl: 'https://play.example.test/x', throws: true);
      await bringReviewUp(tester);

      await tester.tap(find.text('리뷰 남기기'));
      await tester.pump();

      expect(opened, hasLength(1));
      expect(find.text(const UnknownFailure().toDisplayMessage()), findsOneWidget);
    });
  });

  group('리뷰 남기기 — 연타 · 접근성', () {
    testWidgets('여는 호출이 끝나기 전에 다시 눌러도 한 번만 열고, 끝난 뒤에는 다시 열 수 있다', (tester) async {
      final calls = <Uri>[];
      final gate = Completer<bool>();
      await pump(tester, storeUrl: 'https://play.example.test/x', open: (uri) {
        calls.add(uri);
        return gate.future;
      });
      await bringReviewUp(tester);

      await tester.tap(find.text('리뷰 남기기'));
      await tester.tap(find.text('리뷰 남기기'));
      await tester.pump();
      expect(calls, hasLength(1));

      gate.complete(true);
      await tester.pump();
      await tester.tap(find.text('리뷰 남기기'));
      await tester.pump();
      expect(calls, hasLength(2));
    });

    testWidgets('스크린리더에는 버튼으로 읽힌다', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      await bringReviewUp(tester);

      final data = tester.getSemantics(find.text('리뷰 남기기')).getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.flagsCollection.isButton, isTrue);
      handle.dispose();
    });
  });


  // 6칸 그리드 아래 행(pen `M5hpo7`, 대장 10-15). 인스타 칸은 옛 배너(HomeBanner)를 흡수했다.
  group('6칸 그리드 링크 칸', () {
    final instagram = Uri.parse('https://www.instagram.com/campusmate_official');
    Finder tile(String label) => find.descendant(of: find.byType(HomeGrid), matching: find.text(label));

    testWidgets('인스타 칸을 누르면 CampusMate 공식 인스타그램을 기기 앱 · 브라우저로 연다', (tester) async {
      final opened = await pump(tester);

      await tester.tap(tile('인스타그램'));
      await tester.pump();

      expect(opened, [instagram]);
      expect(find.text(const UnknownFailure().toDisplayMessage()), findsNothing);
    });

    testWidgets('인스타를 열지 못하면(false · 예외) 실패 안내를 띄운다', (tester) async {
      for (final throws in [false, true]) {
        final opened = await pump(tester, opens: false, throws: throws);

        await tester.tap(tile('인스타그램'));
        await tester.pump();

        expect(opened, [instagram]);
        expect(find.text(const UnknownFailure().toDisplayMessage()), findsOneWidget);
        await tester.pump(const Duration(seconds: 3));
      }
    });

    testWidgets('이벤트 칸을 누르면 앱 안의 21 이벤트(출시 예정) 화면으로 간다 — 밖으로 열지 않는다', (tester) async {
      final opened = await pump(tester);

      await tester.tap(tile('이벤트'));
      await tester.pumpAndSettle();

      expect(find.text('이벤트 화면'), findsOneWidget);
      expect(opened, isEmpty);
    });

    testWidgets('자리표시 칸은 눌러도 아무 데도 가지 않는다', (tester) async {
      final opened = await pump(tester);

      await tester.tap(tile('곧 열려요'), warnIfMissed: false);
      await tester.pump();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(opened, isEmpty);
    });
  });

  // 10-15 에 잠깐 뺐다가 사용자 요청으로 되살린 완성도 카드(pen `xEpOD`) — 참여 대학 칩 아래.
  group('프로필 완성도 카드', () {
    // 884 화면에서는 카드가 유리 내비 아래에 있다 — 알약 위로 꺼낸다.
    Future<void> bringNudgeUp(WidgetTester tester) async {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('글자를 눌러도 프로필 편집 허브로 간다', (tester) async {
      await pump(tester);
      await bringNudgeUp(tester);

      await tester.tap(find.text('프로필을 조금 더 채우면'));
      await tester.pumpAndSettle();

      expect(find.text('프로필 편집 허브'), findsOneWidget);
    });

    testWidgets('게이지 글자를 눌러도 간다', (tester) async {
      await pump(tester);
      await bringNudgeUp(tester);

      await tester.tap(find.text('프로필 완성도 40%'));
      await tester.pumpAndSettle();

      expect(find.text('프로필 편집 허브'), findsOneWidget);
    });

    testWidgets('오른쪽 끝 화살표 자리를 눌러도 간다 — 카드 전체가 누름 칸이다', (tester) async {
      await pump(tester);
      await bringNudgeUp(tester);
      final card = find.ancestor(of: find.text('프로필을 조금 더 채우면'), matching: find.byType(Container)).last;
      final rect = tester.getRect(card);

      await tester.tapAt(Offset(rect.right - 24, rect.center.dy));
      await tester.pumpAndSettle();

      expect(find.text('프로필 편집 허브'), findsOneWidget);
    });

    testWidgets('편집 허브에서 돌아오면 홈 요약을 다시 읽어 완성도를 맞춘다', (tester) async {
      await pump(tester);
      expect(home.calls, 1);
      await bringNudgeUp(tester);

      await tester.tap(find.text('프로필을 조금 더 채우면'));
      await tester.pumpAndSettle();
      expect(home.calls, 1); // 허브에 있는 동안은 다시 읽지 않는다

      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pump(); // 요약을 다시 읽는 동안 로딩 표시가 계속 움직여 pumpAndSettle 은 끝나지 않는다
      await tester.pump(const Duration(milliseconds: 500));

      expect(home.calls, 2);
    });

    testWidgets('스크린리더에는 버튼으로 읽힌다', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      await bringNudgeUp(tester);

      final node = tester.getSemantics(find.text('프로필을 조금 더 채우면'));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
      handle.dispose();
    });
  });
}
