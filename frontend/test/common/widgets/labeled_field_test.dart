import 'package:campus_mate/common/widgets/labeled_field.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

// 값은 datingApp.pen 마스터 PccKZ(text-field) · 확인 줄 a1eaV, 04-1 보드 mUUet(2026-09-26 campus-pen 값표).
void main() {
  Future<void> pump(
    WidgetTester tester, {
    String? errorText,
    String? successText,
    String? pendingText,
    double textScale = 1.0,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: LabeledField(
              label: '닉네임',
              errorText: errorText,
              successText: successText,
              pendingText: pendingText,
            ),
          ),
        ),
      ),
    );
  }

  BorderSide enabledSide(WidgetTester tester) {
    final field = tester.widget<TextField>(find.byType(TextField));
    return (field.decoration!.enabledBorder! as OutlineInputBorder).borderSide;
  }

  testWidgets('오류가 있으면 입력칸 테두리가 빨간 2px 다', (tester) async {
    await pump(tester, errorText: '이미 있는 닉네임이에요');
    expect(enabledSide(tester), const BorderSide(color: AppColors.error, width: 2));
  });

  testWidgets('확인 중·사용 가능이면 테두리는 기본 1px 그대로다', (tester) async {
    await pump(tester, pendingText: '확인 중…');
    expect(enabledSide(tester), const BorderSide(color: AppColors.outline));
    await pump(tester, successText: '사용할 수 있는 닉네임이에요');
    expect(enabledSide(tester), const BorderSide(color: AppColors.outline));
  });
}
