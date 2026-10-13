import 'package:campus_mate/chat/model/message.dart';
import 'package:campus_mate/chat/view/message_bubble.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_chat_repository.dart';

void main() {
  const body = '제가 자리 먼저 알아볼게요 :)';
  final mine = messageFixture(senderId: myId, body: body, createdAt: DateTime(2026, 10, 13, 14, 15));

  Future<void> pump(WidgetTester tester, Widget bubble, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: const Size(360, 780), textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: bubble),
          ),
        ),
      ),
    );
  }

  Finder unreadMark() => find.text('1');
  Finder bubbleBox() =>
      find.ancestor(of: find.text(body), matching: find.byType(Container)).first;

  group('안 읽음 1(pen RvjRp · Bubble Row UVex8 · 읽음 표시 Qs5As)', () {
    testWidgets('안 읽은 내 말풍선 왼쪽에 1 — 12/600 primary-text #C4224B', (tester) async {
      await pump(tester, MessageBubble(message: mine, isMine: true, isUnread: true));

      final style = tester.widget<Text>(unreadMark()).style!;
      expect((style.fontSize, style.fontWeight, style.color), (12, FontWeight.w600, AppColors.primaryText));
    });

    testWidgets('1 과 말풍선 사이 6, 아래 변이 맞는다(pen UVex8 gap 6 · alignItems end)', (tester) async {
      await pump(tester, MessageBubble(message: mine, isMine: true, isUnread: true));

      final mark = tester.getRect(unreadMark());
      final bubble = tester.getRect(bubbleBox());
      expect((bubble.left - mark.right, bubble.bottom - mark.bottom), (6, 0));
    });

    testWidgets('읽은 말풍선에는 1 이 없고 자리도 차지하지 않는다', (tester) async {
      await pump(tester, MessageBubble(message: mine, isMine: true));

      expect(unreadMark(), findsNothing);
      // 말풍선은 오른쪽 끝(본문 여백 16)에 붙는다 — 꺼진 1 이 폭을 남기지 않는다.
      expect(tester.getRect(bubbleBox()).right, 360 - 16);
    });

    testWidgets('시각을 숨기면(같은 분 묶음의 앞 줄) 시각 줄이 없다', (tester) async {
      await pump(tester, MessageBubble(message: mine, isMine: true, isUnread: true, showTime: false));

      expect(find.text('오후 2:15'), findsNothing);
      expect(unreadMark(), findsOneWidget);
    });

    testWidgets('스크린 리더는 1 이 아니라 "상대가 아직 읽지 않았어요" 를 말풍선과 함께 읽는다', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, MessageBubble(message: mine, isMine: true, isUnread: true));

      expect(find.bySemanticsLabel('1'), findsNothing);
      final label = tester.getSemantics(find.text(body)).label;
      expect(label, contains('상대가 아직 읽지 않았어요'));
      expect(label, contains(body));
      handle.dispose();
    });

    for (final scale in [1.3, 2.0]) {
      testWidgets('글자 확대 $scale 에서 긴 글도 넘치지 않고 1 이 보인다', (tester) async {
        // 여러 줄로 접히는 길이. 목록 안에서는 세로로 스크롤되니 여기서는 가로 넘침만 본다.
        final long = messageFixture(senderId: myId, body: '가' * 40, createdAt: DateTime(2026, 10, 13, 14, 15));
        await pump(tester, MessageBubble(message: long, isMine: true, isUnread: true), textScale: scale);

        expect(tester.takeException(), isNull);
        final mark = tester.getRect(unreadMark());
        expect(mark.left, greaterThanOrEqualTo(16));
        expect(tester.getRect(find.text('오후 2:15')).right, lessThanOrEqualTo(360 - 16));
      });
    }
  });

  testWidgets('상대 말풍선은 그대로다 — 1 이 없다', (tester) async {
    final theirs = messageFixture(senderId: partnerId, body: body, kind: MessageKind.text);
    await pump(tester, MessageBubble(message: theirs, isMine: false));

    expect(unreadMark(), findsNothing);
  });
}
