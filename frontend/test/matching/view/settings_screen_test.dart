import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/view/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_card_repository.dart';

void main() {
  testWidgets('매칭 활성화를 끄면 일시중지 참으로 보낸다', (tester) async {
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

    await tester.tap(find.text('매칭 활성화'));
    await tester.pump();

    expect(repository.pausedValue, isTrue);
  });
}
