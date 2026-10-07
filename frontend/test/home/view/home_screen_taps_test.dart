import 'dart:async';

import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/consent/model/open_url.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/home/model/home_repository_provider.dart';
import 'package:campus_mate/home/model/home_summary.dart';
import 'package:campus_mate/home/model/store_review_url.dart';
import 'package:campus_mate/home/view/home_screen.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../chat/model/fake_chat_repository.dart';
import '../../matching/model/fake_card_repository.dart';
import '../model/fake_home_repository.dart';

/// 홈의 두 누를 곳 — "리뷰 남기기"(스토어 주소가 비어 있는 동안은 "곧 열려요")와 프로필 완성도 카드(→ 프로필 편집 허브).
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

  late FakeHomeRepository home;

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
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pump();
    return opened;
  }

  group('리뷰 남기기', () {
    testWidgets('스토어 주소가 비어 있으면 어디도 안 열고 "곧 열려요" 를 잠깐 보여 준다', (tester) async {
      final opened = await pump(tester);
      expect(find.text('곧 열려요'), findsNothing);

      await tester.tap(find.text('리뷰 남기기'));
      await tester.pump();

      expect(find.text('곧 열려요'), findsOneWidget);
      expect(opened, isEmpty);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('곧 열려요'), findsNothing); // 약 2초 뒤 사라진다(나 탭 안내와 같다)
    });

    testWidgets('주소가 채워져 있으면 그 주소를 열고 안내는 띄우지 않는다', (tester) async {
      final opened = await pump(tester, storeUrl: 'https://play.example.test/store/apps/details?id=app');

      await tester.tap(find.text('리뷰 남기기'));
      await tester.pump();

      expect(opened, [Uri.parse('https://play.example.test/store/apps/details?id=app')]);
      expect(find.text('곧 열려요'), findsNothing);
    });

    testWidgets('주소가 http(s) 가 아니면 열지 않고 "곧 열려요"', (tester) async {
      final opened = await pump(tester, storeUrl: 'not a url');

      await tester.tap(find.text('리뷰 남기기'));
      await tester.pump();

      expect(opened, isEmpty);
      expect(find.text('곧 열려요'), findsOneWidget);
    });

    testWidgets('열기가 false 를 돌려주면 조용히 끝내지 않고 실패 안내를 보여 준다', (tester) async {
      final opened = await pump(tester, storeUrl: 'https://play.example.test/x', opens: false);

      await tester.tap(find.text('리뷰 남기기'));
      await tester.pump();

      expect(opened, hasLength(1));
      expect(find.text(const UnknownFailure().toDisplayMessage()), findsOneWidget);
      expect(find.text('곧 열려요'), findsNothing);
    });

    testWidgets('열기가 예외를 던져도 실패 안내를 보여 준다', (tester) async {
      final opened = await pump(tester, storeUrl: 'https://play.example.test/x', throws: true);

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

      final data = tester.getSemantics(find.text('리뷰 남기기')).getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.flagsCollection.isButton, isTrue);
      handle.dispose();
    });
  });

  group('프로필 완성도 카드', () {
    testWidgets('글자를 눌러도 프로필 편집 허브로 간다', (tester) async {
      await pump(tester);

      await tester.tap(find.text('프로필을 조금 더 채우면'));
      await tester.pumpAndSettle();

      expect(find.text('프로필 편집 허브'), findsOneWidget);
    });

    testWidgets('게이지 글자를 눌러도 간다', (tester) async {
      await pump(tester);

      await tester.tap(find.text('프로필 완성도 40%'));
      await tester.pumpAndSettle();

      expect(find.text('프로필 편집 허브'), findsOneWidget);
    });

    testWidgets('오른쪽 끝 화살표 자리를 눌러도 간다 — 카드 전체가 누름 칸이다', (tester) async {
      await pump(tester);
      final card = find.ancestor(of: find.text('프로필을 조금 더 채우면'), matching: find.byType(Container)).last;
      final rect = tester.getRect(card);

      await tester.tapAt(Offset(rect.right - 24, rect.center.dy));
      await tester.pumpAndSettle();

      expect(find.text('프로필 편집 허브'), findsOneWidget);
    });

    testWidgets('편집 허브에서 돌아오면 홈 요약을 다시 읽어 완성도를 맞춘다', (tester) async {
      await pump(tester);
      expect(home.calls, 1);

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

      final node = tester.getSemantics(find.text('프로필을 조금 더 채우면'));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
      handle.dispose();
    });
  });
}
