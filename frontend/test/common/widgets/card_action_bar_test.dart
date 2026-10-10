import 'package:campus_mate/common/widgets/card_action_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 카드 액션 바(pen `TORAs`) — 글자와 눌림 연결. 결정 버튼 글자는 "대화 신청하기"(지시문 23 F)다.
void main() {
  testWidgets('버튼 글자는 "거절" 과 "대화 신청하기" 이고 옛 "수락하기" 는 없다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: CardActionBar(onReject: () {}, onAccept: () {}))),
    );

    expect(find.text('거절'), findsOneWidget);
    expect(find.text('대화 신청하기'), findsOneWidget);
    expect(find.text('수락하기'), findsNothing);
  });

  testWidgets('각 버튼은 자기 콜백을 부른다', (tester) async {
    var rejected = 0;
    var accepted = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CardActionBar(onReject: () => rejected++, onAccept: () => accepted++)),
      ),
    );

    await tester.tap(find.text('대화 신청하기'));
    await tester.tap(find.text('거절'));

    expect((rejected, accepted), (1, 1));
  });

  testWidgets('배율 1.0 에서는 pen 대로 두 버튼 모두 높이 56 · 거절 폭 104 · 사이 12', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: CardActionBar(onReject: () {}, onAccept: () {}))),
    );

    final reject = tester.getRect(find.ancestor(of: find.text('거절'), matching: find.byType(ElevatedButton)));
    final accept = tester.getRect(find.ancestor(of: find.text('대화 신청하기'), matching: find.byType(ElevatedButton)));
    expect(reject.size, const Size(104, 56));
    expect(accept.height, 56);
    expect(accept.left - reject.right, 12);
  });

  // DESIGN §11.2 — 글꼴 확대 2.0 까지. "대화 신청하기" 는 옛 "수락하기" 보다 길어 한 줄에 안 들어갈 수 있다 —
  // 넘치거나 잘리지 않고 두 줄로 내려가며, 두 버튼은 같은 높이로 함께 커진다.
  for (final scale in [1.3, 1.5, 2.0]) {
    testWidgets('글자 배율 $scale 에서도 넘치지 않고 글자가 잘리지 않으며 두 버튼 높이가 같다', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: CardActionBar(onReject: () {}, onAccept: () {}),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final reject = tester.getSize(find.ancestor(of: find.text('거절'), matching: find.byType(ElevatedButton)));
      final accept = tester.getSize(find.ancestor(of: find.text('대화 신청하기'), matching: find.byType(ElevatedButton)));
      expect(reject.height, accept.height);
      expect(accept.height, greaterThanOrEqualTo(56));
      final paragraph = tester.renderObject<RenderParagraph>(find.text('대화 신청하기'));
      expect(paragraph.getMaxIntrinsicHeight(paragraph.size.width), lessThanOrEqualTo(paragraph.size.height + 0.5));
    });
  }
}
