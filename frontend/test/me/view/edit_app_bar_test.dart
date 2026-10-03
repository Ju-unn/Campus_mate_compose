import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/me/view/edit_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 앞 화면 위에 편집 화면을 올려 둔다 — 뒤로가기는 올린 화면에서만 보인다.
  Future<void> pumpPushed(WidgetTester tester, {String title = '자기소개·태그 수정'}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => Scaffold(appBar: EditAppBar(title: title))),
              ),
              child: const Text('앞 화면'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('앞 화면'));
    await tester.pumpAndSettle();
  }

  testWidgets('pen `iq3jl` · AppBar · Sub `KH1hX` — 높이 56, 뒤로 48×48(x12, arrow-left 22 ink), 제목 `YSMvI` x64 18/700 ink lh1.5', (tester) async {
    await pumpPushed(tester);

    expect(tester.getSize(find.byType(AppBar)).height, 56);
    final back = find.byTooltip('Back');
    expect(tester.getRect(back), const Rect.fromLTWH(12, 4, 48, 48));
    final icon = tester.widget<Icon>(find.byIcon(AppIcons.arrowLeft));
    expect((icon.size, icon.color), (22, AppColors.ink));
    // 제목 x64 = 왼쪽 여백 12 + 뒤로 48 + gap 4(`KH1hX` 2026-10-01 개편 — 옛 8 · x60).
    expect(tester.getTopLeft(find.text('자기소개·태그 수정')).dx, 64);
    final style = tester.widget<Text>(find.text('자기소개·태그 수정')).style!;
    expect((style.fontSize, style.fontWeight, style.color, style.height), (18, FontWeight.w700, AppColors.ink, 1.5));
  });

  testWidgets('뒤로를 누르면 앞 화면으로 돌아간다', (tester) async {
    await pumpPushed(tester);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('앞 화면'), findsOneWidget);
    expect(find.byType(EditAppBar), findsNothing);
  });

  testWidgets('글자 배율 2.0 에서도 제목이 넘치지 않는다', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpPushed(tester, title: '이상형 특징 수정');

    expect(tester.takeException(), isNull);
  });
}
