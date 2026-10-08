import 'package:campus_mate/common/widgets/muted_text_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pen u05wB — 높이 48 · 14/600 muted, 누르면 onPressed', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Column(children: [MutedTextButton(label: '다른 학교 메일 입력', onPressed: () => pressed++)])),
      ),
    );

    expect(tester.getSize(find.byType(InkWell)).height, 48);
    final label = tester.widget<Text>(find.text('다른 학교 메일 입력'));
    expect(label.style!.fontSize, 14);
    expect(label.style!.fontWeight, FontWeight.w600);
    expect(label.style!.color, AppColors.muted);

    await tester.tap(find.text('다른 학교 메일 입력'));
    expect(pressed, 1);
  });
}
