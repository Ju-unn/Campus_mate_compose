import 'package:campus_mate/profile/model/ideal_conditions_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/view/ideal_conditions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_ideal_conditions_repository.dart';
import '../model/fake_onboarding_repository.dart';

void main() {
  Future<void> pump(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        idealConditionsRepositoryProvider.overrideWithValue(FakeIdealConditionsRepository()),
        onboardingRepositoryProvider.overrideWithValue(FakeOnboardingRepository()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: IdealConditionsScreen()),
      ),
    );
  }

  for (final label in ['나이는 상관없어요', '키는 상관없어요']) {
    testWidgets('"$label" 눌림 효과는 화면이 아니라 그 줄이 그린다', (tester) async {
      // 눌림 효과는 가장 가까운 Material 에 그린다 — 그게 Scaffold 면 스크롤해도 테두리만
      // 제자리에 떠 있다(2026-09-27 사용자 실기기, COMMON §4-2).
      await pump(tester);

      final text = find.text(label);
      final row = find.ancestor(of: text, matching: find.byType(InkWell)).first;
      final painter = find.ancestor(of: text, matching: find.byType(Material)).first;

      expect(tester.getSize(painter), tester.getSize(row));
    });
  }
}
