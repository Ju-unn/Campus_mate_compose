import 'package:campus_mate/common/widgets/select_chip.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, {bool isSelected = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SelectChip(label: '여행', isSelected: isSelected, onTap: () {}),
          ),
        ),
      ),
    );
  }

  testWidgets('칩 배경은 칩 안에서 그려진다', (tester) async {
    // `Ink` 는 가장 가까운 Material 에 칠한다 — 그게 Scaffold 면 배경만 화면에 눌러앉아,
    // 태그 목록을 당겼다 놓을 때 글자만 움직이고 회색 칸은 제자리에 남는다(실기기 2026-09-26).
    await pump(tester);

    expect(
      tester.renderObject(find.byType(SelectChip)),
      paints..rrect(color: AppColors.surfaceSoft),
    );
  });

  test('기본 모서리는 알약이다(pen 칩 WzXvK 9999, 2026-10-01 개편 — 옛 8)', () {
    expect(SelectChip(label: '여행', isSelected: false, onTap: () {}).radius, AppRadius.pill);
  });

  testWidgets('고른 칩도 칩 안에서 그려진다', (tester) async {
    await pump(tester, isSelected: true);

    expect(
      tester.renderObject(find.byType(SelectChip)),
      paints..rrect(color: AppColors.primaryWash),
    );
  });

  group('높이 — 평소는 pen 값 그대로, 큰 글씨에서만 글자 높이에 맞춰 늘어난다(DESIGN §11.2)', () {
    Future<void> pumpScaled(WidgetTester tester, double scale, {double height = 35}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Center(child: SelectChip(label: 'E', width: 48, height: height, isSelected: false, onTap: () {})),
            ),
          ),
        ),
      );
    }

    testWidgets('배율 1.0 이면 35(기본) · 44(인상 칩)', (tester) async {
      await pumpScaled(tester, 1);
      expect(tester.getSize(find.byType(SelectChip)), const Size(48, 35));

      await pumpScaled(tester, 1, height: 44);
      expect(tester.getSize(find.byType(SelectChip)), const Size(48, 44));
    });

    testWidgets('배율 2.0 이면 글자 줄이 칩 밖으로 잘리지 않게 칩이 늘어난다', (tester) async {
      await pumpScaled(tester, 2);

      final chip = tester.getSize(find.byType(SelectChip));
      final text = tester.getSize(find.text('E'));
      expect(chip.height, greaterThanOrEqualTo(35));
      expect(text.height + 2, lessThanOrEqualTo(chip.height), reason: '테두리 1 씩을 뺀 안쪽에 글자 줄이 다 들어간다');
      expect(tester.takeException(), isNull);
    });

    testWidgets('"모름"(폭 56)은 배율 2.0 에서 두 줄로 접히지 않고 칩 폭이 늘어난다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: Center(child: SelectChip(label: '모름', width: 56, isSelected: false, onTap: () {})),
            ),
          ),
        ),
      );

      final chip = tester.getSize(find.byType(SelectChip));
      final text = tester.getSize(find.text('모름'));
      expect(text.height, lessThan(40), reason: '한 줄');
      expect(chip.width, greaterThanOrEqualTo(text.width + 2));
      expect(chip.width, greaterThan(56));
    });

    testWidgets('배율 1.0 의 "모름" 은 pen 값 56×35 그대로', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: SelectChip(label: '모름', width: 56, isSelected: false, onTap: () {}))),
        ),
      );

      expect(tester.getSize(find.byType(SelectChip)), const Size(56, 35));
    });
  });
}
