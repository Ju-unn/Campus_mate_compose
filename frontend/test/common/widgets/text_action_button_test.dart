import 'package:campus_mate/common/widgets/text_action_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 값은 datingApp.pen TextButton `UqCmR`(14/600, 채움 · 밑줄 · 아이콘 없음). 높이 · 안쪽 여백 · 색은 쓰는 자리의 인스턴스 값.
void main() {
  Future<void> pump(WidgetTester tester, Widget button) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Column(children: [button])),
      ),
    );
  }

  testWidgets('기본값 — 높이 48 · 안쪽 0 · 14/600 primary-text, 누르면 onPressed', (tester) async {
    var pressed = 0;
    await pump(tester, TextActionButton(label: '학교 추가 요청하기', onPressed: () => pressed++));

    expect(tester.getSize(find.byType(InkWell)).height, 48);
    expect(tester.getSize(find.byType(InkWell)).width, tester.getSize(find.text('학교 추가 요청하기')).width);
    final style = tester.widget<Text>(find.text('학교 추가 요청하기')).style!;
    expect((style.fontSize, style.fontWeight, style.color), (14.0, FontWeight.w600, AppColors.primaryText));

    await tester.tap(find.text('학교 추가 요청하기'));
    expect(pressed, 1);
  });

  testWidgets('높이 · 가로 여백 · 색을 바꿀 수 있다(04-1 "번호 바꾸기" 52 · [0,12])', (tester) async {
    await pump(
      tester,
      TextActionButton(label: '바꾸기', color: AppColors.disabled, height: 52, horizontalPadding: 12, onPressed: () {}),
    );

    final size = tester.getSize(find.byType(InkWell));
    expect(size.height, 52);
    expect(size.width, tester.getSize(find.text('바꾸기')).width + 24);
    expect(tester.widget<Text>(find.text('바꾸기')).style!.color, AppColors.disabled);
  });

  testWidgets('onPressed 가 null 이면 눌리지 않고 꺼진 버튼으로 읽힌다', (tester) async {
    await pump(tester, const TextActionButton(label: '다시 받기', onPressed: null));

    expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
    expect(tester.getSemantics(find.byType(TextActionButton)), isSemantics(isButton: true, isEnabled: false));
  });
}
