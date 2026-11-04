import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/profile/appearance/view/appearance_type_screen.dart';
import 'package:campus_mate/profile/ideal/model/repository/ideal_conditions_repository_provider.dart';
import 'package:campus_mate/profile/ideal/view/ideal_conditions_screen.dart';
import 'package:campus_mate/profile/onboarding/model/repository/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/traits/view/survey_screen.dart';
import 'package:campus_mate/profile/traits/view/tag_picker_screen.dart';
import 'package:campus_mate/profile/traits/viewmodel/tag_picker_kind.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../ideal/model/repository/fake_ideal_conditions_repository.dart';
import '../model/repository/fake_onboarding_repository.dart';

/// 하단 CTA 바(pen `A8INC6` [8,24,8,24], 2026-10-01 개편 — 옛 [16,24,28,24]). 버튼은 좌우 24 · 화면 바닥 위 8 이다.
void main() {
  final screens = <String, Widget>{
    'AppearanceTypeScreen': const AppearanceTypeScreen(),
    'IdealConditionsScreen': const IdealConditionsScreen(),
    'SurveyScreen': const SurveyScreen(),
    'TagPickerScreen': const TagPickerScreen(kind: TagPickerKind.interests),
  };

  for (final MapEntry(key: name, value: screen) in screens.entries) {
    testWidgets('$name 아래 버튼은 좌우 24 · 바닥 위 8 이다', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            idealConditionsRepositoryProvider.overrideWithValue(FakeIdealConditionsRepository()),
            onboardingRepositoryProvider.overrideWithValue(FakeOnboardingRepository()),
          ],
          child: MaterialApp(home: screen),
        ),
      );
      await tester.pump();

      final button = tester.getRect(find.byType(AppButton).last);
      expect(button.left, 24);
      expect(button.right, 800 - 24);
      expect(button.bottom, 600 - 8);
    });
  }
}
