import 'package:campus_mate_admin/widgets/admin_pager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 표 아래 번호 쪽 나누기: 전체 N건 · 이전 · 번호 10개 묶음 · 다음
void main() {
  final pressed = <int>[];

  Future<void> pump(WidgetTester tester, {required int total, required int page, int size = 20}) async {
    pressed.clear();
    tester.view.physicalSize = const Size(1400, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AdminPager(total: total, page: page, size: size, onPage: pressed.add)),
    ));
  }

  List<int> numbers() => [
        for (var n = 1; n <= 400; n++)
          if (find.byKey(ValueKey('pager-page-$n')).evaluate().isNotEmpty) n,
      ];

  bool enabled(WidgetTester tester, String key) {
    final box = find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(InkWell));
    return tester.widget<InkWell>(box.first).onTap != null;
  }

  testWidgets('전체 건수는 늘 보인다', (tester) async {
    await pump(tester, total: 1234, page: 1);
    expect(tester.widget<Text>(find.byKey(const ValueKey('pager-total'))).data, '전체 1,234건');
  });

  testWidgets('한 쪽뿐이어도 이전 [1] 다음을 보이고 이전 · 다음은 꺼진다', (tester) async {
    await pump(tester, total: 20, page: 1);
    expect(numbers(), [1]);
    expect(enabled(tester, 'pager-prev'), isFalse);
    expect(enabled(tester, 'pager-next'), isFalse);
    expect(find.text('전체 20건'), findsOneWidget);
  });

  testWidgets('번호는 실제 쪽 수까지만(21건이면 1 2)', (tester) async {
    await pump(tester, total: 21, page: 1);
    expect(numbers(), [1, 2]);
    expect(enabled(tester, 'pager-next'), isFalse);
  });

  testWidgets('0건이면 번호 줄을 숨긴다', (tester) async {
    await pump(tester, total: 0, page: 1);
    expect(find.byKey(const ValueKey('pager-prev')), findsNothing);
    expect(find.byKey(const ValueKey('pager-next')), findsNothing);
    expect(numbers(), isEmpty);
    expect(find.text('전체 0건'), findsOneWidget);
  });

  testWidgets('첫 묶음은 1~10, 이전은 꺼지고 다음은 11쪽으로', (tester) async {
    await pump(tester, total: 400, page: 3); // 20쪽
    expect(numbers(), [for (var n = 1; n <= 10; n++) n]);
    expect(enabled(tester, 'pager-prev'), isFalse);
    expect(enabled(tester, 'pager-next'), isTrue);
    await tester.tap(find.byKey(const ValueKey('pager-next')));
    expect(pressed, [11]);
  });

  testWidgets('13쪽이면 11~20, 이전은 10쪽으로, 끝 묶음이라 다음은 꺼진다', (tester) async {
    await pump(tester, total: 400, page: 13);
    expect(numbers(), [for (var n = 11; n <= 20; n++) n]);
    expect(enabled(tester, 'pager-next'), isFalse);
    await tester.tap(find.byKey(const ValueKey('pager-prev')));
    expect(pressed, [10]);
  });

  testWidgets('끝 묶음이 덜 차면 마지막 쪽까지만', (tester) async {
    await pump(tester, total: 241, page: 12); // 13쪽
    expect(numbers(), [11, 12, 13]);
  });

  testWidgets('번호를 누르면 그 쪽, 지금 쪽은 눌러도 아무 일 없다', (tester) async {
    await pump(tester, total: 100, page: 2);
    await tester.tap(find.byKey(const ValueKey('pager-page-4')));
    await tester.tap(find.byKey(const ValueKey('pager-page-2')));
    expect(pressed, [4]);
  });

  testWidgets('좁은 칸(검수 목록 320)에서는 번호가 접혀 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(1400, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 320, child: AdminPager(total: 400, page: 1, size: 20, onPage: (_) {})),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(numbers(), [for (var n = 1; n <= 10; n++) n]);
  });

  testWidgets('번호 칸의 눌림 효과는 칸이 칠한다(COMMON 4-2)', (tester) async {
    await pump(tester, total: 100, page: 1);
    final cell = find.byKey(const ValueKey('pager-page-2'));
    final ink = find.descendant(of: cell, matching: find.byType(InkWell)).first;
    final material = find.ancestor(of: ink, matching: find.byType(Material)).first;
    expect(tester.getSize(material), tester.getSize(ink));
  });
}
