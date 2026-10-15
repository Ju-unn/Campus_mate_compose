import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/view/hint_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _text = '사진을 길게 눌러 끌면 순서를 바꿀 수 있어요. 첫 칸이 대표 사진이에요.';

void main() {
  Future<void> pump(WidgetTester tester, {double textScale = 1}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: const Scaffold(body: SizedBox(width: 200, child: HintLine(_text))),
        ),
      ),
    );
  }

  // pen 04-2 설명 줄(대장 전달 10-15): 3D 안내 아이콘 18 → 8 → 14/400 muted, 아이콘은 첫 줄 높이 안 가운데.
  testWidgets('파란 안내 3D 아이콘 18 · 글과 8 · 14/400 muted', (tester) async {
    await pump(tester);

    final icon = tester.widget<Icon3d>(find.byType(Icon3d));
    expect((icon.icon, icon.size), (AppIcon3d.infoBlue, 18));
    expect(tester.widget<Text>(find.text(_text)).style, AppTypography.bodySmall.copyWith(color: AppColors.muted));
    expect(tester.getRect(find.text(_text)).left, tester.getRect(find.byType(Icon3d)).right + 8);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('글이 여러 줄이어도 아이콘은 첫 줄 높이 가운데에 선다(글자 $scale배)', (tester) async {
      await pump(tester, textScale: scale);

      final text = tester.getRect(find.text(_text));
      final icon = tester.getRect(find.byType(Icon3d));
      final firstLine = 14 * scale * AppTypography.bodySmall.height!;
      // 좁은 칸이라 두 줄 이상이다 — 아이콘이 글 전체 가운데로 내려가면 안 된다.
      expect(text.height, greaterThan(firstLine * 1.5));
      expect(icon.center.dy, closeTo(text.top + firstLine / 2, 0.5));
      expect(tester.takeException(), isNull);
    });
  }
}
