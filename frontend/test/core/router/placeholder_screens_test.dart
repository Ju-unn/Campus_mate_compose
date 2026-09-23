import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/router/placeholder_screens.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../chat/model/fake_chat_repository.dart';
import '../../matching/model/fake_card_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('스플래시 화면은 로딩 스피너 없이 "CampusMate" 문구만 headline 스타일로 보인다', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));

    expect(find.text('CampusMate'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    final text = tester.widget<Text>(find.text('CampusMate'));
    expect(text.style?.fontSize, AppTypography.headline.fontSize);
    expect(text.style?.fontWeight, AppTypography.headline.fontWeight);
  });

  group('준비 중 화면의 톱니', () {
    Future<GoRouter> pumpTab(WidgetTester tester, AppTab tab) async {
      final container = ProviderContainer(
        overrides: [
          chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
          cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
        ],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: '/coming-soon',
        routes: [
          GoRoute(
            path: '/coming-soon',
            builder: (context, state) => ComingSoonScreen(tab: tab),
          ),
          GoRoute(
            path: AppRoutes.settings,
            builder: (context, state) => const Scaffold(body: Text('설정 화면')),
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
      await tester.pump();
      return router;
    }

    testWidgets('"나" 탭에서는 톱니로 설정에 들어간다', (tester) async {
      // pen 에서 설정(16)으로 가는 문은 15 내 프로필 `r8oJc` 의 톱니 하나뿐이다.
      await pumpTab(tester, AppTab.me);

      await tester.tap(find.byIcon(AppIcons.settings));
      await tester.pumpAndSettle();

      expect(find.text('설정 화면'), findsOneWidget);
    });

    testWidgets('다른 탭에는 톱니가 없다', (tester) async {
      await pumpTab(tester, AppTab.community);

      expect(find.byIcon(AppIcons.settings), findsNothing);
    });
  });
}
