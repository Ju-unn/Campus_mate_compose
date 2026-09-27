import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/view/settings_screen.dart';
import 'package:campus_mate/safety/model/safety_repository_provider.dart';
import 'package:campus_mate/safety/view/block_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../safety/model/fake_safety_repository.dart';
import '../model/fake_card_repository.dart';

void main() {
  Future<FakeCardRepository> pump(WidgetTester tester) async {
    final repository = FakeCardRepository();
    final container = ProviderContainer(
      overrides: [
        cardRepositoryProvider.overrideWithValue(repository),
        safetyRepositoryProvider.overrideWithValue(FakeSafetyRepository()),
      ],
    );
    addTearDown(container.dispose);
    // 줄을 누르면 push 로 다음 화면이 열린다 — 라우터 안에서 띄운다.
    final router = GoRouter(
      initialLocation: AppRoutes.settings,
      routes: [
        GoRoute(path: AppRoutes.settings, builder: (context, state) => const SettingsScreen()),
        GoRoute(path: AppRoutes.blockList, builder: (context, state) => const BlockListScreen()),
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
    return repository;
  }

  Finder tile(String title) => find.ancestor(of: find.text(title), matching: find.byType(ListTile));

  testWidgets('매칭 활성화를 끄면 일시중지 참으로 보낸다', (tester) async {
    final repository = await pump(tester);

    await tester.tap(find.text('매칭 활성화'));
    await tester.pump();

    expect(repository.pausedValue, isTrue);
  });

  testWidgets('"차단 목록" 줄은 알림 바로 아래, user-x 아이콘이다(pen lMDpY 8번 o0km6)', (tester) async {
    await pump(tester);

    expect(tile('차단 목록'), findsOneWidget);
    expect(tester.getRect(tile('차단 목록')).top, tester.getRect(tile('알림')).bottom);
    expect(find.descendant(of: tile('차단 목록'), matching: find.byIcon(AppIcons.userX)), findsOneWidget);
    expect(find.descendant(of: tile('차단 목록'), matching: find.byIcon(AppIcons.chevronRight)), findsOneWidget);
  });

  testWidgets('"차단 목록" 을 누르면 16f 차단 목록이 열린다', (tester) async {
    await pump(tester);

    await tester.tap(find.text('차단 목록'));
    await tester.pumpAndSettle();

    expect(find.byType(BlockListScreen), findsOneWidget);
  });

  testWidgets('모든 줄의 눌림 효과는 그 줄 안에서 그려진다', (tester) async {
    // 잉크는 가장 가까운 Material 에 그린다 — 그게 Scaffold 면 목록을 밀어도 테두리가 제자리에 떠 있다(COMMON §4-2).
    // 스위치 줄도 안에 ListTile 을 두므로 ListTile 만 훑으면 나중에 더해지는 줄까지 같이 본다.
    await pump(tester);

    final tiles = find.byType(ListTile);
    expect(tiles, findsWidgets);
    for (var i = 0; i < tiles.evaluate().length; i++) {
      final material = find.ancestor(of: tiles.at(i), matching: find.byType(Material)).first;
      expect(tester.getSize(material), tester.getSize(tiles.at(i)));
    }
  });
}
