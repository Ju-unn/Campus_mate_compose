import 'package:campus_mate/common/widgets/mbti_pole_toggle.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
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

  // 선호 MBTI 안내(2026-11-02 앱 1.0.1, pen 06-1 `QrUdQ` 안내 `MED5L`) — 서버는 축마다 따로 봐서 두 극을 다 골라도 그 축은 상관없다.
  // 안내는 제목 옆이 아니라 칩 묶음 아래다: 섹션 `soTqZ` 세로 gap 8, 12/normal #6A6A6A, 한 줄 자동 폭.
  group('MBTI 안내(pen `MED5L`)', () {
    const hintText = '고르지 않거나 둘 다 고르면 상관없어요.';

    Future<void> pumpAt(WidgetTester tester, {required double textScale}) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester);
    }

    testWidgets('칩 묶음 아래 8 에 한 줄(12/1.4) 왼쪽 정렬 muted 로 놓이고 제목 줄에는 없다', (tester) async {
      await pumpAt(tester, textScale: 1);

      final hint = find.text(hintText);
      expect(hint, findsOneWidget);
      expect(find.text('선택하지 않으면 상관없어요.'), findsNothing);
      final toggle = find.byType(MbtiPoleToggle);
      expect(tester.getTopLeft(hint).dy - tester.getBottomLeft(toggle).dy, 8); // 칩 아래 간격 8
      expect(tester.getTopLeft(hint).dx, 24); // 화면 좌우 여백
      expect(tester.getSize(hint).height, closeTo(12 * 1.4, 0.5)); // 한 줄(줄 높이는 정수 픽셀로 맞춰져 17)
      final style = tester.widget<Text>(hint).style!;
      expect((style.fontSize, style.fontWeight, style.color), (12, FontWeight.w400, AppColors.muted));
      // 제목 `IhhKP` 줄에는 안내가 없다 — 제목은 글자 하나뿐이다.
      final titleRow = find.ancestor(of: find.text('선호하는 성향 (MBTI)'), matching: find.byType(Row)).first;
      expect(find.descendant(of: titleRow, matching: find.text(hintText)), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('글자 1.5배 · 폭 360 에서도 넘치지 않고 화면 안쪽 여백 안이다', (tester) async {
      await pumpAt(tester, textScale: 1.5);

      final hint = find.text(hintText);
      expect(hint, findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(tester.getRect(hint).right, lessThanOrEqualTo(360 - 24));
      expect(tester.getTopLeft(hint).dy, greaterThan(tester.getBottomLeft(find.byType(MbtiPoleToggle)).dy));
    });
  });

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
