import 'package:campus_mate/common/widgets/alert_sheet.dart';
import 'package:campus_mate/common/widgets/sheet_handle.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpAt(WidgetTester tester, Widget sheet) {
    phone(tester);
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: sheet)),
      ),
    );
  }

  group('SheetFrame(pen AlertSheet D0TvG 틀)', () {
    testWidgets('캔버스 · 위 모서리 24 · 위쪽 그림자, 화면 폭 전체', (tester) async {
      await pumpAt(tester, const SheetFrame(child: SizedBox(height: 100)));

      final frame = find.byType(SheetFrame);
      expect(tester.getSize(frame), const Size(360, 100));
      final decoration =
          tester.widget<Container>(find.descendant(of: frame, matching: find.byType(Container))).decoration! as BoxDecoration;
      expect(decoration.color, AppColors.canvas);
      expect(decoration.borderRadius, const BorderRadius.vertical(top: Radius.circular(24)));
      expect(decoration.boxShadow, AppElevation.top);
    });

    testWidgets('아래 안전 영역은 비운다(위는 비우지 않는다)', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(padding: const EdgeInsets.only(top: 40, bottom: 20)),
            child: child!,
          ),
          home: const Scaffold(body: Align(alignment: Alignment.bottomCenter, child: SheetFrame(child: SizedBox(height: 100)))),
        ),
      );

      // 내용 100 + 아래 안전 영역 20, 위 안전 영역은 더하지 않는다.
      expect(tester.getSize(find.byType(SheetFrame)).height, 120);
    });
  });

  group('AlertSheet — 손잡이 칸 위아래 12 · 안쪽 [16,8,16,32] · 스크롤', () {
    testWidgets('손잡이는 위에서 12, 내용은 왼쪽 16 · 손잡이 칸 아래 8, 맨 아래 32 여백', (tester) async {
      await pumpAt(
        tester,
        const AlertSheet(
          children: [Text('제목', key: ValueKey('first')), SizedBox(height: 10), Text('끝', key: ValueKey('last'))],
        ),
      );

      final sheet = tester.getRect(find.byType(AlertSheet));
      final handle = tester.getRect(find.byType(SheetHandle));
      expect(handle.size, const Size(36, 4));
      expect(handle.top - sheet.top, 12);
      expect(handle.center.dx, 180);
      final first = tester.getRect(find.byKey(const ValueKey('first')));
      expect(first.left, 16);
      expect(first.top - handle.bottom, 12 + 8);
      expect(sheet.bottom - tester.getRect(find.byKey(const ValueKey('last'))).bottom, 32);
    });

    testWidgets('내용은 가로로 꽉 찬다(328)', (tester) async {
      await pumpAt(tester, const AlertSheet(children: [SizedBox(key: ValueKey('box'), height: 10)]));

      expect(tester.getSize(find.byKey(const ValueKey('box'))).width, 328);
    });

    testWidgets('화면보다 길면 넘치지 않고 스크롤한다', (tester) async {
      await pumpAt(tester, const AlertSheet(children: [SizedBox(height: 2000)]));

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });
}
