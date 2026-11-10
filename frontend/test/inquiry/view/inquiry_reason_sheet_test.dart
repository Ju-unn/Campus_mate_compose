import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/inquiry/model/data/inquiry_reason.dart';
import 'package:campus_mate/inquiry/view/inquiry_reason_sheet.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/safety/view/reason_radio_row.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  InquiryReason? result;
  late bool closed;

  /// pen 보드와 같은 360×780 화면에서 시트를 연다.
  Future<void> open(WidgetTester tester, {InquiryReason? current, double scale = 1}) async {
    result = null;
    closed = false;
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
              onPressed: () async {
                result = await showInquiryReasonSheet(context, current: current);
                closed = true;
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  SafetySheetButton confirmButton(WidgetTester tester) =>
      tester.widget<SafetySheetButton>(find.widgetWithText(SafetySheetButton, '선택하기'));

  testWidgets('pen Ywu44 문구 — 제목, 사유 여섯 줄, 선택하기와 취소', (tester) async {
    await open(tester);

    expect(find.text('무엇을 문의할까요?'), findsOneWidget);
    for (final label in ['계정 · 인증', '결제 · 하트', '매칭 · 카드', '신고 · 안전', '앱 오류', '기타']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byType(ReasonRadioRow), findsNWidgets(6));
    expect(find.text('선택하기'), findsOneWidget);
    expect(find.text('취소'), findsOneWidget);
  });

  testWidgets('사유 줄은 신고 시트와 같은 부품이라 누르는 영역이 48 이상이다', (tester) async {
    await open(tester);

    for (final row in tester.widgetList<ReasonRadioRow>(find.byType(ReasonRadioRow)).toList().asMap().keys) {
      final rect = tester.getRect(find.byType(ReasonRadioRow).at(row));
      expect(rect.height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('아무것도 안 골랐으면 선택하기를 누를 수 없다', (tester) async {
    await open(tester);

    expect(confirmButton(tester).onPressed, isNull);
  });

  testWidgets('열 때 지금 고른 사유가 이미 골라져 있고 선택하기를 누를 수 있다', (tester) async {
    await open(tester, current: InquiryReason.payment);

    final selected = tester.widgetList<ReasonRadioRow>(find.byType(ReasonRadioRow)).where((row) => row.isSelected);
    expect(selected.map((row) => row.label), ['결제 · 하트']);
    expect(confirmButton(tester).onPressed, isNotNull);
  });

  testWidgets('사유를 고르고 선택하기를 누르면 그 사유를 돌려주며 닫힌다', (tester) async {
    await open(tester);

    await tester.tap(find.text('앱 오류'));
    await tester.pump();
    expect(confirmButton(tester).onPressed, isNotNull);
    await tester.tap(find.text('선택하기'));
    await tester.pumpAndSettle();

    expect(result, InquiryReason.bug);
    expect(find.byType(SafetySheet), findsNothing);
  });

  testWidgets('다른 사유로 바꾸면 하나만 골라진 채 바뀐다', (tester) async {
    await open(tester, current: InquiryReason.payment);

    await tester.tap(find.text('기타'));
    await tester.pump();

    final selected = tester.widgetList<ReasonRadioRow>(find.byType(ReasonRadioRow)).where((row) => row.isSelected);
    expect(selected.map((row) => row.label), ['기타']);
  });

  testWidgets('취소를 누르면 고르던 것을 버리고 null 로 닫힌다', (tester) async {
    await open(tester, current: InquiryReason.payment);

    await tester.tap(find.text('앱 오류'));
    await tester.pump();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(result, isNull);
  });

  testWidgets('시트 바탕은 흰색이고 뒤는 모달 딤이다', (tester) async {
    await open(tester);

    final sheet = tester.widget<Container>(find.descendant(of: find.byType(SafetySheet), matching: find.byType(Container)).first);
    expect((sheet.decoration! as BoxDecoration).color, AppColors.canvas);
  });

  testWidgets('글자 2배에서도 넘치거나 잘리는 글자가 없다', (tester) async {
    await open(tester, current: InquiryReason.account, scale: 2);

    expect(tester.takeException(), isNull);
  });
}
