import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/view/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_card_repository.dart';

void main() {
  Future<FakeCardRepository> pump(WidgetTester tester) async {
    final repository = FakeCardRepository();
    final container = ProviderContainer(
      overrides: [cardRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();
    return repository;
  }

  testWidgets('매칭 활성화를 끄면 일시중지 참으로 보낸다', (tester) async {
    final repository = await pump(tester);

    await tester.tap(find.text('매칭 활성화'));
    await tester.pump();

    expect(repository.pausedValue, isTrue);
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
