import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../chat/model/fake_chat_repository.dart';
import '../../matching/model/fake_card_repository.dart';

void main() {
  Future<void> pump(WidgetTester tester, FakeChatRepository chat) async {
    final container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(chat),
        // 뱃지는 "수락 대기 + 안 읽은 메시지" 합이라 카드 쪽 저장소도 본다(§8.8).
        cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: AppRoutes.today,
      routes: [
        GoRoute(
          path: AppRoutes.today,
          builder: (context, state) =>
              const Scaffold(bottomNavigationBar: AppBottomNav(current: AppTab.today)),
        ),
        GoRoute(
          path: AppRoutes.conversations,
          builder: (context, state) => const Scaffold(body: Text('대화 목록')),
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
  }

  testWidgets('뱃지가 세 자리면 99+ 로 줄여 보여준다', (tester) async {
    // §8.8 하한 — 숫자가 길어져도 바가 밀리지 않는다.
    final chat = FakeChatRepository()
      ..conversations = Success([conversationFixture(unreadCount: 105)]);

    await pump(tester, chat);

    expect(find.text('99+'), findsOneWidget);
    expect(find.text('105'), findsNothing);
  });

  testWidgets('"대화" 를 누르면 대화 목록으로 간다', (tester) async {
    await pump(tester, FakeChatRepository());

    await tester.tap(find.text('대화'));
    await tester.pumpAndSettle();

    expect(find.text('대화 목록'), findsOneWidget);
  });
}
