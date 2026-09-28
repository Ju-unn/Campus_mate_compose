import 'package:campus_mate/billing/view/heart_task_pending_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const MaterialApp(home: HeartTaskPendingScreen()));
  }

  testWidgets('pen 18c — 마스코트 88 · 제목 · 설명 두 줄, 앱바 · 버튼 없음', (tester) async {
    await pump(tester);

    expect(tester.getSize(find.byType(Image)), const Size(88, 88));
    expect(find.text('확인하고 있어요'), findsOneWidget);
    expect(find.text('확인이 끝나면 무료로 하트 모으기 목록에서 결과를 볼 수 있어요'), findsOneWidget);
    expect(find.text('보통 영업일 1~2일 걸려요'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(tester.getSize(find.text('확인이 끝나면 무료로 하트 모으기 목록에서 결과를 볼 수 있어요')).width, lessThanOrEqualTo(280));
  });

  testWidgets('내용 묶음은 화면 가운데다', (tester) async {
    await pump(tester);

    final title = tester.getRect(find.text('확인하고 있어요'));
    expect(title.center.dx, closeTo(180, 1));
  });

  testWidgets('글자 2배에서도 넘침 예외가 없다', (tester) async {
    await pump(tester, textScale: 2);

    expect(tester.takeException(), isNull);
  });
}
