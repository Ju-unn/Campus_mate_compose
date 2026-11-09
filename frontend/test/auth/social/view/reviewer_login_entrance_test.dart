import 'dart:io';

import 'package:campus_mate/auth/social/view/reviewer_login_entrance.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// 보이지 않는 입구 하나만 100×100 으로 놓은 화면. 입구 밑에는 긴 목록을 깔아 두어, 입구가 밑의 스크롤을 막지 않는지도 본다.
Future<({int Function() opened, ScrollController list})> _pump(WidgetTester tester) async {
  var opened = 0;
  final list = ScrollController();
  addTearDown(list.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: ListView(controller: list, children: [for (var i = 0; i < 40; i++) SizedBox(height: 60, child: Text('row $i'))]),
            ),
            Positioned(left: 0, top: 0, width: 100, height: 100, child: ReviewerLoginEntrance(onOpen: () => opened++)),
          ],
        ),
      ),
    ),
  );
  return (opened: () => opened, list: list);
}

Future<void> _tap(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.tapAt(const Offset(50, 50));
    await tester.pump();
  }
}

void main() {
  testWidgets('일곱 번 누르면 onOpen 을 한 번 부른다', (tester) async {
    final probe = await _pump(tester);

    await _tap(tester, 7);

    expect(probe.opened(), 1);
  });

  testWidgets('여섯 번만 누르면 부르지 않는다', (tester) async {
    final probe = await _pump(tester);

    await _tap(tester, 6);

    expect(probe.opened(), 0);
  });

  testWidgets('열린 뒤 다시 일곱 번 누르면 또 연다 — 열기 직전까지 센 탭은 이월되지 않는다', (tester) async {
    final probe = await _pump(tester);

    await _tap(tester, 7);
    await _tap(tester, 6);
    expect(probe.opened(), 1);
    await _tap(tester, 1);

    expect(probe.opened(), 2);
  });

  testWidgets('입구 밖을 누르면 세지 않는다', (tester) async {
    final probe = await _pump(tester);

    for (var i = 0; i < 7; i++) {
      await tester.tapAt(const Offset(150, 50));
      await tester.pump();
    }

    expect(probe.opened(), 0);
  });

  testWidgets('입구는 투명하다 — 입구 위에서 끌어도 밑의 목록이 그대로 스크롤된다(큰 글자로 시작 화면을 밀어 올리는 손길)', (tester) async {
    final probe = await _pump(tester);

    await tester.drag(find.byType(ReviewerLoginEntrance), const Offset(0, -200));
    await tester.pump();

    expect(probe.list.offset, greaterThan(0));
    expect(probe.opened(), 0);
  });

  testWidgets('낭독기에서 뺀다 — 일반 사용자에게 보이지 않는 기능이라 접근성 트리에 탭 동작을 올리지 않는다', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    final node = tester.getSemantics(find.byType(ReviewerLoginEntrance));

    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    handle.dispose();
  });

  // 심사원은 스토어에서 받은 릴리스 빌드로 시험한다 — 디버그 전용 · 빌드 값 스위치로 막으면 입구가 없는 앱이 나간다.
  test('릴리스 빌드에서도 동작한다 — 입구 · 시트 · 뷰모델 소스에 디버그 · 빌드 값 조건이 없다', () {
    const files = [
      'lib/auth/social/view/reviewer_login_entrance.dart',
      'lib/auth/social/view/reviewer_login_sheet.dart',
      'lib/auth/social/view/start_view.dart',
      'lib/auth/social/viewmodel/reviewer_login_view_model.dart',
      'lib/auth/social/model/data/tap_streak.dart',
    ];
    final guards = RegExp(r'kDebugMode|kReleaseMode|kProfileMode|assert\s*\(|fromEnvironment|Env\.');

    final offenders = [
      for (final path in files)
        if (guards.hasMatch(File(path).readAsStringSync())) path,
    ];

    expect(offenders, isEmpty);
  });
}
