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
}
