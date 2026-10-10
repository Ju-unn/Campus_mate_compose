import 'package:campus_mate/common/widgets/select_chip.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:campus_mate/profile/view/appearance_pickers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 320dp 짜리 좁은 기기에서 04-4·06-1 이 주는 폭 그대로 그린다 — 여기서 안 넘치면 어디서도 안 넘친다.
  Future<void> pumpNarrow(WidgetTester tester, Widget picker) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: SizedBox(width: 320 - AppSpacing.lg * 2, child: picker)),
        ),
      ),
    );
  }

  testWidgets('동물상 8종이 좁은 화면에서도 4열로 다 보인다', (tester) async {
    await pumpNarrow(tester, AnimalTypePicker(selected: const {}, onTap: (_) {}));

    for (final type in AnimalType.values) {
      expect(find.text(type.label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('인상 5종은 3개 + 2개 두 줄로 균등하게 나뉜다', (tester) async {
    await pumpNarrow(tester, ImpressionTypePicker(selected: const {}, onTap: (_) {}));

    for (final type in ImpressionType.values) {
      expect(find.text(type.label), findsOneWidget);
    }
    // 글자 폭이 아니라 칸 폭으로 나눈다 — 첫 줄 3개는 서로 같고, 둘째 줄 2개는 그보다 넓다.
    final chips = find.byType(SelectChip);
    final widths = [for (var i = 0; i < ImpressionType.values.length; i++) tester.getSize(chips.at(i)).width];
    expect(widths[0], widths[1]);
    expect(widths[1], widths[2]);
    expect(widths[3], widths[4]);
    expect(widths[3], greaterThan(widths[0]));
    expect(tester.takeException(), isNull);
  });

  testWidgets('인상 칩 높이는 pen 값 44 다', (tester) async {
    // pen `BGMWX` 40 → 44(2026-09-26 erd3 수정). 손가락이 닿는 칸을 44 로 키운 값이다.
    await pumpNarrow(tester, ImpressionTypePicker(selected: const {}, onTap: (_) {}));

    expect(tester.getSize(find.byType(SelectChip).first).height, 44);
  });

  group('동물상 — 글자 확대(DESIGN §11.2)', () {
    Future<void> pumpScaled(WidgetTester tester, double scale, {double width = 312}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(width: width, child: AnimalTypePicker(selected: const {}, onTap: (_) {})),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('배율 1.0 이면 pen 값 그대로 312×232(칸 72×112 · 간격 8)', (tester) async {
      await pumpScaled(tester, 1);

      final size = tester.getSize(find.byType(AnimalTypePicker));
      expect(size.width, closeTo(312, 0.01));
      expect(size.height, closeTo(232, 0.01));
    });

    for (final scale in [1.3, 1.5, 2.0]) {
      testWidgets('배율 $scale 에서도 이름이 칸 밖으로 넘치지 않는다(칸이 이름 높이만큼 늘어난다)', (tester) async {
        await pumpScaled(tester, scale);

        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(AnimalTypePicker)).height, greaterThanOrEqualTo(231.99));
      });
    }

    testWidgets('좁은 기기(폭 272)에서 배율 2.0 이어도 넘치지 않는다', (tester) async {
      await pumpScaled(tester, 2, width: 272);

      expect(tester.takeException(), isNull);
    });
  });

  // 눌림 효과는 가장 가까운 Material 에 그린다 — 그게 Scaffold 면 스크롤해도 테두리만 떠 있다(COMMON §4-2).
  testWidgets('동물상 칸 눌림 효과는 화면이 아니라 칸이 그린다', (tester) async {
    await pumpNarrow(tester, AnimalTypePicker(selected: const {}, onTap: (_) {}));

    final text = find.text(AnimalType.values.first.label);
    final cell = find.ancestor(of: text, matching: find.byType(InkWell)).first;
    final painter = find.ancestor(of: text, matching: find.byType(Material)).first;

    expect(tester.getSize(painter), tester.getSize(cell));
  });
}
