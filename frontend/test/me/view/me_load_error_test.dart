import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/me/view/me_load_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 나 탭 화면(15 · 15-4 · 15-5)이 같이 쓰는 읽기 실패 모양 — pen 에 없는 상태(계획서 N9).
void main() {
  Future<void> pump(WidgetTester tester, VoidCallback onRetry) {
    return tester.pumpWidget(MaterialApp(home: Scaffold(body: MeLoadError(onRetry: onRetry))));
  }

  testWidgets('가운데 "잠시 뒤 다시 시도해 주세요"(16/400 body) 와 "다시 시도" 글자 버튼 — 공통 오류 문구가 아니다', (tester) async {
    await pump(tester, () {});

    final message = find.text('잠시 뒤 다시 시도해 주세요');
    expect(message, findsOneWidget);
    final style = tester.widget<Text>(message).style!;
    expect((style.fontSize, style.fontWeight, style.color), (16, FontWeight.w400, AppColors.body));
    expect(find.text(const UnknownFailure().toDisplayMessage()), findsNothing);
    final retry = tester.widget<AppButton>(find.byType(AppButton));
    expect((retry.label, retry.variant), ('다시 시도', AppButtonVariant.text));
    expect(tester.getCenter(message).dx, 400);
  });

  testWidgets('"다시 시도" 를 누르면 onRetry 가 불린다', (tester) async {
    var retries = 0;
    await pump(tester, () => retries++);

    await tester.tap(find.text('다시 시도'));

    expect(retries, 1);
  });
}
