import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/confirm_popup.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/safety/view/block_confirm.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool? confirmed;

  setUp(() => confirmed = null);

  Future<void> open(WidgetTester tester, {double scale = 1}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => confirmed = await confirmBlock(context, '토끼'),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  testWidgets('공용 확인 팝업 위험 변형 — 제목 · 줄인 설명(사용자 2026-11-16) · 빨강 "차단"', (tester) async {
    await open(tester);

    expect(find.byKey(confirmPopupCardKey), findsOneWidget);
    expect(find.text('토끼 님을 차단할까요?'), findsOneWidget);
    expect(
      find.text('대화는 내 목록에서 사라지고, 서로의 카드에 다시 나타나지 않아요. 차단은 설정 > 차단 목록에서 해제할 수 있어요.'),
      findsOneWidget,
    );
    expect(tester.widget<AppButton>(find.widgetWithText(AppButton, '차단')).variant, AppButtonVariant.dangerStrong);
  });

  testWidgets('차단을 누르면 true', (tester) async {
    await open(tester);

    await tester.tap(find.text('차단'));
    await tester.pumpAndSettle();

    expect(confirmed, isTrue);
  });

  testWidgets('취소나 바깥 탭은 false', (tester) async {
    await open(tester);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(confirmed, isFalse);

    confirmed = null;
    await tester.tap(find.text('열기'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(180, 20));
    await tester.pumpAndSettle();
    expect(confirmed, isFalse);
  });

  testWidgets('글자 2배에서도 넘치거나 잘리는 글자가 없다', (tester) async {
    await open(tester, scale: 2);

    expect(tester.takeException(), isNull);
    for (final paragraph in tester.renderObjectList<RenderParagraph>(
        find.descendant(of: find.byKey(confirmPopupCardKey), matching: find.byType(RichText)))) {
      expect(paragraph.getMaxIntrinsicHeight(paragraph.size.width),
          lessThanOrEqualTo(paragraph.size.height + 0.5),
          reason: paragraph.text.toPlainText());
    }
  });
}
