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

  // 사용자 요청 11-22: 「페이징 화면 중앙 아래에 배치」 — 번호 줄은 가로 가운데, 건수는 그 위 왼쪽(겹치지 않게)
  Rect numberRow(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey('pager-prev'))).expandToInclude(tester.getRect(find.byKey(const ValueKey('pager-next'))));

  testWidgets('넓은 칸: 한 줄(높이 36) — 번호 줄(이전 … 다음)은 가로 가운데, 전체 N건은 같은 줄 왼쪽 끝(겹치지 않게)', (tester) async {
    await pump(tester, total: 400, page: 1);
    final pager = tester.getRect(find.byType(AdminPager));
    final row = numberRow(tester);
    final total = tester.getRect(find.byKey(const ValueKey('pager-total')));
    expect(pager.height, 36, reason: '표 아래 다른 줄(안내 글 등)의 자리가 그대로');
    expect(row.center.dx, moreOrLessEquals(pager.center.dx, epsilon: 0.5));
    expect(total.left, pager.left);
    expect(total.right, lessThanOrEqualTo(row.left));
    expect(total.center.dy, moreOrLessEquals(row.center.dy, epsilon: 0.5));
  });

  testWidgets('한 줄로 놓이는 가장 좁은 폭(720)에서 두 자리 번호 · 큰 건수여도 넘치지 않고 겹치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(1400, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 720, child: AdminPager(total: 1234567, page: 13, size: 20, onPage: (_) {})),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    // 시험 글꼴(글자마다 정사각)에서는 건수 자리를 남기면 번호가 두 줄로 접힌다 — 묶음 전체가 가운데이고 건수와 겹치지 않는다
    final block = tester.getRect(find.descendant(of: find.byType(AdminPager), matching: find.byType(Wrap)));
    expect(block.center.dx, moreOrLessEquals(360, epsilon: 0.5));
    expect(tester.getRect(find.byKey(const ValueKey('pager-total'))).right, lessThanOrEqualTo(block.left));
  });

  testWidgets('한 줄 폭(760)이어도 글자 2배 · 세 자리 번호(101쪽~)면 번호가 접혀 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(1400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(1400, 600), textScaler: TextScaler.linear(2)),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 760, child: AdminPager(total: 2100, page: 101, size: 1, onPage: (_) {})),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(numbers(), [for (var n = 101; n <= 110; n++) n]);
  });

  testWidgets('한 쪽뿐이어도 이전 [1] 다음은 가운데', (tester) async {
    await pump(tester, total: 3, page: 1);
    expect(numberRow(tester).center.dx, moreOrLessEquals(tester.getRect(find.byType(AdminPager)).center.dx, epsilon: 0.5));
  });

  testWidgets('좁은 칸(320)에서도 번호 줄은 가운데로 접히고 건수와 겹치지 않는다', (tester) async {
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
    final total = tester.getRect(find.byKey(const ValueKey('pager-total')));
    final first = tester.getRect(find.byKey(const ValueKey('pager-prev')));
    expect(total.bottom, lessThanOrEqualTo(first.top));
    // 첫 줄(이전 1 2 …)의 양쪽 여백이 같다 — 왼쪽으로 몰리지 않는다
    final firstLine = [
      for (final key in ['pager-prev', for (var n = 1; n <= 10; n++) 'pager-page-$n', 'pager-next'])
        if (tester.getRect(find.byKey(ValueKey(key))).top == first.top) tester.getRect(find.byKey(ValueKey(key))),
    ].reduce((a, b) => a.expandToInclude(b));
    expect(firstLine.left, moreOrLessEquals(320 - firstLine.right, epsilon: 4));
  });

  testWidgets('번호 칸의 눌림 효과는 칸이 칠한다(COMMON 4-2)', (tester) async {
    await pump(tester, total: 100, page: 1);
    final cell = find.byKey(const ValueKey('pager-page-2'));
    final ink = find.descendant(of: cell, matching: find.byType(InkWell)).first;
    final material = find.ancestor(of: ink, matching: find.byType(Material)).first;
    expect(tester.getSize(material), tester.getSize(ink));
  });
}
