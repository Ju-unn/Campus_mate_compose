import 'dart:async';

import 'package:campus_mate/core/push/push_route.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// 알림을 눌러 연 화면 밑에 홈이 깔려 있어야 뒤로가기가 홈으로 간다(2026-10-19 사용자: "에브리타임 승인 알림을 눌러 들어가면 뒤로가기가 없다").
void main() {
  GoRouter routerAt(String initial) => GoRouter(
        initialLocation: initial,
        routes: [
          for (final path in [
            AppRoutes.today,
            AppRoutes.conversations,
            AppRoutes.heartTasks,
            '${AppRoutes.heartTaskSubmit}/:task',
            '${AppRoutes.chatRoom}/:matchId',
            AppRoutes.friendReviews,
          ])
            GoRoute(path: path, builder: (context, state) => Text(state.uri.toString())),
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const Text('home'),
            routes: [GoRoute(path: 'friend-reviews/write/:profileId', builder: (context, state) => const Text('write'))],
          ),
        ],
      );

  Future<GoRouter> pumpAt(WidgetTester tester, String initial) async {
    final router = routerAt(initial);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  /// 맨 위 화면의 주소. 쌓은(push) 화면은 설정의 uri 가 아니라 마지막 조각이 가진다.
  String top(GoRouter router) {
    final last = router.routerDelegate.currentConfiguration.last;
    return last is ImperativeRouteMatch ? last.matches.uri.toString() : router.routerDelegate.currentConfiguration.uri.toString();
  }

  Future<void> open(WidgetTester tester, GoRouter router, String path) async {
    PushRoute.open(router, path);
    await tester.pumpAndSettle();
  }

  // 꺼진 앱(시작 위치 오늘 탭 등 아무 데나) · 앱이 떠 있을 때 모두 같은 함수를 지난다.
  for (final path in [
    AppRoutes.heartTasks,
    '${AppRoutes.heartTaskSubmit}/everytime_post?reason=date_missing',
    AppRoutes.friendReviews,
  ]) {
    testWidgets('$path 를 알림으로 열면 홈 위에 쌓여 뒤로가기가 홈으로 간다', (tester) async {
      final router = await pumpAt(tester, AppRoutes.today);

      await open(tester, router, path);

      expect(top(router), path);
      expect(router.canPop(), isTrue);
      router.pop();
      await tester.pumpAndSettle();
      expect(top(router), AppRoutes.home);
      expect(router.canPop(), isFalse);
    });
  }

  testWidgets('이미 깊이 들어가 있어도 알림을 누르면 [홈, 목적지] 로 새로 쌓는다', (tester) async {
    final router = await pumpAt(tester, AppRoutes.home);
    unawaited(router.push<void>(AppRoutes.friendReviews));
    await tester.pumpAndSettle();

    await open(tester, router, AppRoutes.heartTasks);

    expect(top(router), AppRoutes.heartTasks);
    router.pop();
    await tester.pumpAndSettle();
    expect(top(router), AppRoutes.home);
    expect(router.canPop(), isFalse);
  });

  for (final path in [AppRoutes.today, AppRoutes.conversations, '/chat/m1', '${AppRoutes.friendReviewWrite}/p1']) {
    testWidgets('$path 는 탭 · 채팅방 · 홈 위 시트라 그대로 간다(밑에 홈을 더 깔지 않는다)', (tester) async {
      final router = await pumpAt(tester, AppRoutes.home);

      await open(tester, router, path);

      expect(top(router), path);
      // 홈 아래 시트는 홈이 이미 밑에 있다. 나머지는 쌓인 것이 없다.
      expect(router.canPop(), path.startsWith(AppRoutes.friendReviewWrite));
    });
  }
}
