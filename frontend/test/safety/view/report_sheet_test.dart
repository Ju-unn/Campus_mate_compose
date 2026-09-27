import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/safety/model/safety_errors.dart';
import 'package:campus_mate/safety/model/safety_repository.dart';
import 'package:campus_mate/safety/model/safety_repository_provider.dart';
import 'package:campus_mate/safety/view/report_sheet.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:campus_mate/safety/viewmodel/report_ui_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_safety_repository.dart';

void main() {
  late FakeSafetyRepository repository;
  ReportSheetResult? result;
  late bool closed;

  setUp(() {
    repository = FakeSafetyRepository();
    result = null;
    closed = false;
  });

  /// pen 보드와 같은 360×780 화면에서 시트를 연다.
  Future<void> open(WidgetTester tester, {double scale = 1}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = ProviderContainer(
      overrides: [safetyRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showReportSheet(context, const ReportTarget.message('msg-7'));
                  closed = true;
                },
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  SafetySheetButton submitButton(WidgetTester tester) =>
      tester.widget<SafetySheetButton>(find.widgetWithText(SafetySheetButton, '신고하기'));

  testWidgets('pen yl8gX 문구 — 제목과 사유 다섯 줄', (tester) async {
    await open(tester);

    expect(find.text('무엇을 신고할까요?'), findsOneWidget);
    for (final label in ['욕설·비방·혐오', '성적 불쾌감', '광고·스팸', '사칭·허위', '기타']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('사유를 고르기 전에는 신고하기를 누를 수 없다', (tester) async {
    await open(tester);
    expect(submitButton(tester).onPressed, isNull);

    await tester.tap(find.text('광고·스팸'));
    await tester.pump();

    expect(submitButton(tester).onPressed, isNotNull);
  });

  testWidgets('기타를 골랐을 때만 여러 줄 상자와 카운터가 뜬다', (tester) async {
    await open(tester);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('사칭·허위'));
    await tester.pump();
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('기타'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('어떤 점이 불편했는지 알려주세요.'), findsOneWidget);
    expect(find.text('0 / 200'), findsOneWidget);
    // pen `UbMxg` 320×104.
    expect(tester.getSize(find.byKey(reportNoteBoxKey)), const Size(320, 104));
    // 카운터는 상자 안 왼쪽 아래(pen `BCwSP` x 12).
    final box = tester.getRect(find.byKey(reportNoteBoxKey));
    final counter = tester.getRect(find.text('0 / 200'));
    expect(counter.left, box.left + 12);
    expect(counter.bottom, box.bottom - 12);
  });

  testWidgets('기타 메모는 코드포인트 200 개에서 자른다', (tester) async {
    await open(tester);
    await tester.tap(find.text('기타'));
    await tester.pumpAndSettle();

    const family = '👨‍👩‍👧'; // 코드포인트 5개
    await tester.enterText(find.byType(TextField), '${'ㄱ' * 190}$family$family$family');
    await tester.pump();

    final text = tester.widget<TextField>(find.byType(TextField)).controller!.text;
    expect(text.runes.length, 200);
    expect(find.text('200 / 200'), findsOneWidget);
  });

  testWidgets('실패하면 시트를 연 채 빨간 한 줄을 띄우고, 다시 누르면 같은 요청을 보낸다', (tester) async {
    repository.reportResult = const FailureResult(NetworkFailure());
    await open(tester);
    await tester.tap(find.text('광고·스팸'));
    await tester.pump();

    await tester.tap(find.text('신고하기'));
    await tester.pumpAndSettle();

    expect(find.text('무엇을 신고할까요?'), findsOneWidget);
    final error = tester.widget<Text>(find.text('네트워크 연결을 확인해 주세요'));
    expect(error.style!.color, AppColors.error);
    expect(closed, isFalse);

    await tester.tap(find.text('신고하기'));
    await tester.pumpAndSettle();
    expect(repository.reports, hasLength(2));
    expect(repository.reports.last.target, {'target_type': 'message', 'target_id': 'msg-7'});
  });

  testWidgets('성공하면 시트가 닫히고 결과와 안내 문구를 돌려준다', (tester) async {
    await open(tester);
    await tester.tap(find.text('욕설·비방·혐오'));
    await tester.pump();

    await tester.tap(find.text('신고하기'));
    await tester.pumpAndSettle();

    expect(find.text('무엇을 신고할까요?'), findsNothing);
    expect(closed, isTrue);
    expect(result!.outcome, ReportOutcome.reported);
    expect(result!.message, reportedMessage);
  });

  testWidgets('하루 상한이면 닫고 상한 문구를 돌려준다', (tester) async {
    repository.reportResult = const FailureResult(RateLimitedFailure());
    await open(tester);
    await tester.tap(find.text('욕설·비방·혐오'));
    await tester.pump();

    await tester.tap(find.text('신고하기'));
    await tester.pumpAndSettle();

    expect(result!.outcome, ReportOutcome.limited);
    expect(result!.message, reportLimitedMessage);
  });

  testWidgets('취소하면 아무것도 보내지 않고 null 로 닫힌다', (tester) async {
    await open(tester);
    await tester.tap(find.text('광고·스팸'));
    await tester.pump();

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(result, isNull);
    expect(repository.reports, isEmpty);
  });

  group('사유 행', () {
    Finder rowInk(String label) =>
        find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;

    testWidgets('행은 pen RadioRow 높이 48 이고 라디오 줄(24)은 그 가운데다', (tester) async {
      await open(tester);

      final visible = find.ancestor(of: find.text('광고·스팸'), matching: find.byType(Row)).first;
      expect(tester.getSize(visible).height, 24);
      expect(tester.getSize(rowInk('광고·스팸')).height, greaterThanOrEqualTo(48));
    });

    testWidgets('눌림 효과는 행 안의 Material 에 그린다(COMMON §4-2)', (tester) async {
      await open(tester);

      final material = find.ancestor(of: rowInk('광고·스팸'), matching: find.byType(Material)).first;
      expect(tester.getSize(material), tester.getSize(rowInk('광고·스팸')));
    });
  });

  testWidgets('pen 크기 — 손잡이 36×4, 버튼 320×52, 제목은 시트 위에서 32', (tester) async {
    await open(tester);

    final sheet = tester.getRect(find.byType(SafetySheet));
    expect(sheet.width, 360);
    expect(tester.getSize(find.byType(SheetHandle)), const Size(36, 4));
    expect(tester.getTopLeft(find.text('무엇을 신고할까요?')).dy - sheet.top, 32);
    expect(tester.getSize(find.widgetWithText(SafetySheetButton, '신고하기')), const Size(320, 52));
    expect(tester.getSize(find.widgetWithText(SafetySheetButton, '취소')), const Size(320, 52));
  });

  group('세로 자리(pen yl8gX · 흐름 보드 NGoHN, 간격 16/4/0/4/36/16)', () {
    double topOf(WidgetTester tester, String label, Rect sheet) =>
        tester.getTopLeft(find.widgetWithText(SafetySheetButton, label)).dy - sheet.top;

    testWidgets('기타를 골라 입력칸이 뜬 상태(pen 이 그린 상태) — 시트 594, 신고하기 446, 취소 514', (tester) async {
      await open(tester);
      await tester.tap(find.text('기타'));
      await tester.pumpAndSettle();

      final sheet = tester.getRect(find.byType(SafetySheet));
      // 사유 목록 `MY7UX` 는 행 48 × 5, 간격 0 — 제목 아래 4.
      expect(tester.getTopLeft(find.text('욕설·비방·혐오')).dy - sheet.top, greaterThan(62));
      expect(tester.getRect(find.byKey(reportNoteBoxKey)).top - sheet.top, 32 + 274);
      expect(topOf(tester, '신고하기', sheet), 446);
      expect(topOf(tester, '취소', sheet), 514);
      expect(sheet.height, 594);
    });

    testWidgets('입력칸이 없을 때도 목록과 버튼 사이는 36 이다(pen 자동 배치에서 입력칸만 빠진 모양)', (tester) async {
      await open(tester);

      final sheet = tester.getRect(find.byType(SafetySheet));
      // 제목 32 + 26, 간격 4, 목록 240, 간격 36.
      expect(topOf(tester, '신고하기', sheet), 32 + 26 + 4 + 240 + 36);
      expect(sheet.height, 594 - 4 - 104);
    });
  });

  testWidgets('글자 2배에서도 넘치거나 잘리는 글자가 없다', (tester) async {
    await open(tester, scale: 2);
    await tester.tap(find.text('기타'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 시트가 화면보다 길어지면 스크롤로 버튼까지 닿는다.
    await tester.scrollUntilVisible(find.text('취소'), 100,
        // 첫 Scrollable 이 시트 본문이다(메모 입력칸 안에도 하나 있다).
        scrollable: find.descendant(of: find.byType(SafetySheet), matching: find.byType(Scrollable)).first);
    expect(find.text('취소').hitTestable(), findsOneWidget);
    for (final paragraph in tester.renderObjectList<RenderParagraph>(
        find.descendant(of: find.byType(SafetySheet), matching: find.byType(RichText)))) {
      expect(paragraph.getMaxIntrinsicHeight(paragraph.size.width), lessThanOrEqualTo(paragraph.size.height + 0.5),
          reason: paragraph.text.toPlainText());
    }
  });
}
