import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/matching/view/row_with_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 줄 + 버튼 띠(pen INViw 보낸 신청 · 프로필 보기, pdOvf 거절한 카드 줄). 값은 UI값표 CT5Lq 0-1.
void main() {
  const rowKey = Key('row');

  Future<void> pump(WidgetTester tester, RowWithActions widget) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(alignment: Alignment.topLeft, child: SizedBox(width: 328, child: widget)),
        ),
      ),
    );
  }

  Widget button(String label) => AppButton(label: label, onPressed: () {}, size: AppButtonSize.small);

  testWidgets('INViw: 72 줄 → 8 → 44 버튼 하나(폭 꽉) = 328x124', (tester) async {
    await pump(
      tester,
      RowWithActions(row: const SizedBox(key: rowKey, height: 72), actions: [button('프로필 보기')]),
    );

    expect(tester.getSize(find.byType(RowWithActions)), const Size(328, 124));
    expect(tester.getRect(find.byType(AppButton)), const Rect.fromLTWH(0, 80, 328, 44));
  });

  testWidgets('pdOvf: 줄 → 12 → 버튼 둘(같은 폭, 사이 8) = 328x128', (tester) async {
    await pump(
      tester,
      RowWithActions(
        row: const SizedBox(key: rowKey, height: 72),
        gap: 12,
        actions: [button('프로필 보기'), button('다시 신청하기')],
      ),
    );

    expect(tester.getSize(find.byType(RowWithActions)), const Size(328, 128));
    final buttons = find.byType(AppButton);
    expect(tester.getRect(buttons.at(0)), const Rect.fromLTWH(0, 84, 160, 44));
    expect(tester.getRect(buttons.at(1)), const Rect.fromLTWH(168, 84, 160, 44));
  });

  testWidgets('H75rq: 아래 여백 12 를 더하면 328x136', (tester) async {
    await pump(
      tester,
      RowWithActions(
        row: const SizedBox(key: rowKey, height: 72),
        bottomPadding: 12,
        actions: [button('프로필 보기')],
      ),
    );

    expect(tester.getSize(find.byType(RowWithActions)), const Size(328, 136));
  });
}
