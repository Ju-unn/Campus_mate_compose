import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/widgets/count_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// pen Web/NavBadge(l9ZEF0): 높이 20 · 좌우 6 · 알약 · web-danger 바탕 · 12/700 web-on-primary. 0 숨김, 100 이상 "99+".
void main() {
  setUpAll(() async {
    final loader = FontLoader('Pretendard')..addFont(rootBundle.load('assets/fonts/Pretendard-Bold.otf'));
    await loader.load();
  });

  Future<void> pump(WidgetTester tester, int count) {
    return tester.pumpWidget(MaterialApp(home: Center(child: CountBadge(count: count))));
  }

  testWidgets('badge caps at 99+ and hides at 0', (tester) async {
    await pump(tester, 0);
    expect(find.byType(Text), findsNothing);
    expect(tester.getSize(find.byType(CountBadge)), Size.zero);

    await pump(tester, -2);
    expect(find.byType(Text), findsNothing);

    await pump(tester, 7);
    expect(find.text('7'), findsOneWidget);

    await pump(tester, 99);
    expect(find.text('99'), findsOneWidget);

    await pump(tester, 100);
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('pen 값: 높이 20 · 좌우 6 · 알약 web-danger · 12/700 흰 글자, 한 자리는 거의 원(폭 19 안팎)', (tester) async {
    await pump(tester, 3);

    final box = tester.getRect(find.byType(CountBadge));
    expect(box.height, 20);
    final text = tester.getRect(find.text('3'));
    expect(text.left - box.left, 6);
    expect(box.right - text.right, 6);
    expect(box.width, closeTo(19, 1.5));
    final decoration = tester.widget<Container>(find.descendant(of: find.byType(CountBadge), matching: find.byType(Container))).decoration! as BoxDecoration;
    expect(decoration.color, AdminColors.danger);
    expect(decoration.borderRadius, BorderRadius.circular(9999));
    final style = tester.widget<Text>(find.text('3')).style!;
    expect((style.fontSize, style.fontWeight, style.color), (12, FontWeight.w700, AdminColors.onPrimary));
  });
}
