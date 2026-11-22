import 'package:campus_mate_admin/widgets/admin_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 공용 표의 머리 칸 정렬(사용자 목록, 사용자 요청 11-22) — 정렬을 주지 않은 표는 그대로다.
void main() {
  final tapped = <int>[];

  Future<void> pump(WidgetTester tester, {AdminTableSort? sort}) async {
    tapped.clear();
    tester.view.physicalSize = const Size(1200, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AdminTable(
          columns: const [200, 200, 200],
          heads: const ['닉네임', '받은 신고', '가입일'],
          sort: sort,
          rows: const [AdminTableRow(cells: [Text('a'), Text('b'), Text('c')])],
        ),
      ),
    ));
  }

  AdminTableSort sortOn(int current, {bool ascending = true}) =>
      AdminTableSort(columns: const {0, 2}, current: current, ascending: ascending, onSort: tapped.add);

  Finder headTap(String head) => find.ancestor(of: find.text(head), matching: find.byType(InkWell));

  testWidgets('정렬을 주지 않으면 머리 칸은 글자뿐(누를 곳 · 화살표 없음)', (tester) async {
    await pump(tester);

    for (final head in ['닉네임', '받은 신고', '가입일']) {
      expect(headTap(head), findsNothing, reason: head);
    }
    expect(find.byIcon(LucideIcons.arrowUp), findsNothing);
    expect(find.byIcon(LucideIcons.arrowDown), findsNothing);
  });

  testWidgets('정렬할 수 있는 칸만 눌린다 — 누르면 그 칸 번호, 정렬 못 하는 칸(받은 신고)은 글자뿐', (tester) async {
    await pump(tester, sort: sortOn(2, ascending: false));

    await tester.tap(find.text('닉네임'));
    await tester.tap(find.text('가입일'));
    await tester.tap(find.text('받은 신고'));

    expect(tapped, [0, 2]);
    expect(headTap('받은 신고'), findsNothing);
  });

  testWidgets('지금 정렬 칸에만 화살표 — 오름차순 위, 내림차순 아래', (tester) async {
    await pump(tester, sort: sortOn(0));
    expect(find.byIcon(LucideIcons.arrowUp), findsOneWidget);
    expect(find.byIcon(LucideIcons.arrowDown), findsNothing);
    expect(tester.getRect(find.byIcon(LucideIcons.arrowUp)).left, greaterThan(tester.getRect(find.text('닉네임')).right));

    await pump(tester, sort: sortOn(2, ascending: false));
    expect(find.byIcon(LucideIcons.arrowDown), findsOneWidget);
    expect(find.byIcon(LucideIcons.arrowUp), findsNothing);
    expect(tester.getRect(find.byIcon(LucideIcons.arrowDown)).left, greaterThan(tester.getRect(find.text('가입일')).right));
  });

  testWidgets('화면 읽기: 정렬 칸은 단추, 지금 칸은 고름 + 방향을 읽는다', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, sort: sortOn(2, ascending: false));

    expect(tester.getSemantics(headTap('가입일')), isSemantics(label: '가입일, 내림차순 정렬됨', isButton: true, isSelected: true));
    expect(tester.getSemantics(headTap('닉네임')), isSemantics(label: '닉네임, 눌러서 정렬', isButton: true, isSelected: false));
    semantics.dispose();
  });

  testWidgets('키보드: Tab 으로 머리 칸에 가서 Enter 로 정렬한다', (tester) async {
    await pump(tester, sort: sortOn(2));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(tapped, [0]);
  });
}
