import 'dart:math' as math;

import 'package:campus_mate/chat/view/chat_list_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_chat_repository.dart';

void main() {
  Future<void> pumpBadge(WidgetTester tester, {required double scale, int count = 3}) async {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    // 실제 행과 같은 자리 — Row 안 Column 이라 가로·세로 모두 제한이 없다.
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(mainAxisSize: MainAxisSize.min, children: [UnreadBadge(count: count)]),
          ],
        ),
      ),
    ));
  }

  RenderParagraph badgeParagraph(WidgetTester tester) => tester.renderObject<RenderParagraph>(
        find.descendant(of: find.byType(UnreadBadge), matching: find.byType(RichText)),
      );

  testWidgets('배율 1.0 에서는 pen 대로 높이 20 알약이다', (tester) async {
    await pumpBadge(tester, scale: 1.0);

    final size = tester.getSize(find.byType(UnreadBadge));
    expect(size.height, 20.0);
    // 폭은 최소 20 에 숫자 + 좌우 6 이 넘치면 늘어난다. 테스트 글꼴은 숫자가 글자 크기만큼 넓어
    // 한 자리도 20 을 넘는다 — 실기기 Pretendard 한 자리는 20 안에 든다.
    expect(size.width, math.max(20.0, badgeParagraph(tester).size.width + 12));
  });

  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    testWidgets('글자 배율 $scale 에서 배지 숫자가 알약에 잘리지 않는다(백로그 28)', (tester) async {
      // 고정 높이 상자 안의 글자는 넘침 오류 없이 조용히 잘린다 — 글자 상자를 직접 잰다.
      await pumpBadge(tester, scale: scale, count: 120);

      final paragraph = badgeParagraph(tester);
      expect(paragraph.text.toPlainText(), '99+');
      expect(
        paragraph.getMaxIntrinsicHeight(paragraph.size.width),
        lessThanOrEqualTo(paragraph.size.height + 0.5),
      );
      expect(
        paragraph.getMinIntrinsicWidth(double.infinity),
        lessThanOrEqualTo(paragraph.size.width + 0.5),
      );
      expect(tester.takeException(), isNull);
    });
  }

  group('대화 행(pen `L061P2`)', () {
    Future<void> pumpRow(WidgetTester tester, {required double scale}) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      // 실제 화면처럼 리스트 안 — 세로 제한이 없다.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ChatListRow(conversation: conversationFixture(unreadCount: 120), onTap: () {}),
            ],
          ),
        ),
      ));
    }

    testWidgets('배율 1.0 에서는 pen 대로 높이 72 다', (tester) async {
      await pumpRow(tester, scale: 1.0);

      expect(tester.getSize(find.byType(ChatListRow)).height, 72.0);
    });

    testWidgets('눌림 효과는 화면이 아니라 행이 그린다(§4-2)', (tester) async {
      // `InkWell` 은 가장 가까운 Material 에 그린다 — 그게 Scaffold 면 목록을 움직여도
      // 눌림 테두리가 제자리에 남아 공중에 뜬다(실기기 2026-09-27).
      await pumpRow(tester, scale: 1.0);

      final tile = find.descendant(of: find.byType(ChatListRow), matching: find.byType(InkWell));
      final painter = find.ancestor(of: tile, matching: find.byType(Material)).first;

      expect(tester.getSize(painter), tester.getSize(find.byType(ChatListRow)));
    });

    for (final scale in [1.0, 1.3, 1.5, 2.0]) {
      testWidgets('글자 배율 $scale 에서 행 글자가 넘치거나 잘리지 않는다(백로그 28 곁)', (tester) async {
        await pumpRow(tester, scale: scale);

        // 고정 height 72 면 Column 이 넘친다(1.75 부터) — 넘침 오류와 조용한 잘림을 둘 다 본다.
        expect(tester.takeException(), isNull);
        final clipped = [
          for (final element in find
              .descendant(of: find.byType(ChatListRow), matching: find.byType(RichText))
              .evaluate())
            if (element.renderObject case final RenderParagraph p
                when p.getMaxIntrinsicHeight(p.size.width) > p.size.height + 0.5)
              p.text.toPlainText(),
        ];
        expect(clipped, isEmpty);
      });
    }
  });
}
