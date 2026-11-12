import 'dart:async';

import 'package:campus_mate/chat/model/repository/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/consent/model/repository/open_url.dart';
import 'package:campus_mate/core/l10n/error_text.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/home/model/data/home_summary.dart';
import 'package:campus_mate/home/model/repository/home_repository_provider.dart';
import 'package:campus_mate/home/view/home_grid.dart';
import 'package:campus_mate/home/view/home_screen.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/l10n/app_localizations_ko.dart';
import 'package:campus_mate/matching/model/repository/card_repository_provider.dart';
import 'package:campus_mate/me/model/repository/me_repository_provider.dart';
import 'package:campus_mate/notifications/model/repository/notifications_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../chat/model/repository/fake_chat_repository.dart';
import '../../matching/model/repository/fake_card_repository.dart';
import '../../me/model/repository/fake_me_repository.dart';
import '../model/repository/fake_home_repository.dart';
import '../../notifications/model/repository/fake_notifications_repository.dart';

/// 홈의 누를 곳 — 링크 칸 인스타그램 · 에브리타임(홈 v3 `kkKiZ`, 11-12), 프로필 완성도 카드(→ 프로필 편집 허브).
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

  /// 홈을 띄우고 openExternalUrlProvider 가 받은 주소들을 돌려준다. [opens] 는 그 호출이 돌려줄 값, [throws] 면 예외.
  Future<List<Uri>> pump(
    WidgetTester tester, {
    bool opens = true,
    bool throws = false,
    Future<bool> Function(Uri)? open,
  }) async {
    tester.view.physicalSize = const Size(360, 884); // pen 프레임 — 링크 칸 · 카드가 화면 안에 든다
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
        openExternalUrlProvider.overrideWithValue(
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
      UncontrolledProviderScope(container: container, child: MaterialApp.router(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, routerConfig: router)),
    );
    await tester.pump();
    return opened;
  }

  // 링크 칸 2개(pen `C3J23d`) — 둘 다 기기 앱 · 브라우저로 연다. 에브리타임은 https 주소라 앱이 있으면 앱, 없으면 웹이 열린다.
  group('링크 칸', () {
    final links = {
      '인스타그램': Uri.parse('https://www.instagram.com/campusmate_official'),
      '에브리타임': Uri.parse('https://everytime.kr'),
    };
    Finder tile(String label) => find.descendant(of: find.byType(HomeGrid), matching: find.text(label));

    for (final MapEntry(key: label, value: link) in links.entries) {
      testWidgets('$label 칸을 누르면 $link 를 기기 앱 · 브라우저로 연다', (tester) async {
        final opened = await pump(tester);

        await tester.tap(tile(label));
        await tester.pump();

        expect(opened, [link]);
        expect(find.text(failureText(AppLocalizationsKo(), const UnknownFailure())), findsNothing);
      });

      testWidgets('$label 을 열지 못하면(false · 예외) 실패 안내를 띄운다', (tester) async {
        for (final throws in [false, true]) {
          final opened = await pump(tester, opens: false, throws: throws);

          await tester.tap(tile(label));
          await tester.pump();

          expect(opened, [link]);
          expect(find.text(failureText(AppLocalizationsKo(), const UnknownFailure())), findsOneWidget);
          await tester.pump(const Duration(seconds: 3));
        }
      });
    }

    testWidgets('여는 호출이 끝나기 전에 다시 눌러도 한 번만 열고, 끝난 뒤에는 다시 열 수 있다', (tester) async {
      final calls = <Uri>[];
      final gate = Completer<bool>();
      await pump(tester, open: (uri) {
        calls.add(uri);
        return gate.future;
      });

      await tester.tap(tile('에브리타임'));
      await tester.pump();
      await tester.tap(tile('에브리타임'));
      await tester.pump();
      expect(calls, hasLength(1));

      gate.complete(true);
      await tester.pump();
      await tester.tap(tile('에브리타임'));
      await tester.pump();
      expect(calls, hasLength(2));
    });

    testWidgets('이벤트 · 곧 열려요 칸은 없다 — 이벤트 화면으로 가는 길이 홈에서 빠졌다', (tester) async {
      await pump(tester);

      expect(find.text('이벤트'), findsNothing);
      expect(find.text('곧 열려요'), findsNothing);
    });
  });

  // 10-15 에 잠깐 뺐다가 사용자 요청으로 되살린 완성도 카드(pen `xEpOD`) — 참여 대학 칩 아래.
  group('프로필 완성도 카드', () {
    // 884 화면에서는 카드가 유리 내비 아래에 있을 수 있다 — 알약 위로 꺼낸다.
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
