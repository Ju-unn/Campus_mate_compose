import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('leading 이 없으면 글자만 그리고 앞 간격도 없다(15d-3)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Center(child: AppToast(label: '하트 10개를 받았어요'))));

    // 안쪽 여백 16 만 — 16 칸 그림 자리 + 간격 8 이 남아 있으면 40 이 된다.
    final toast = tester.getRect(find.byType(AppToast));
    final label = tester.getRect(find.text('하트 10개를 받았어요'));
    expect(label.left - toast.left, AppSpacing.md);
    expect(find.descendant(of: find.byType(AppToast), matching: find.byType(Icon)), findsNothing);
  });
}
