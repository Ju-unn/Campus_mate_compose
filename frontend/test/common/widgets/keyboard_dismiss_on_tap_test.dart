import 'package:campus_mate/common/widgets/keyboard_dismiss_on_tap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 2026-10-14 사용자 피드백 9 — 키보드는 입력칸 밖 빈 곳을 누르면 내려간다(여러 줄 입력은 '완료' 키가 없다).
// 앱처럼 MaterialApp.builder 로 감싸 화면 · 시트 전부에 걸리게 한다.
void main() {
  late FocusNode first;
  late FocusNode second;
  var sent = 0;

  Future<void> pump(WidgetTester tester) async {
    first = FocusNode();
    second = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    sent = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => KeyboardDismissOnTap(child: child!),
        home: Scaffold(
          body: ListView(
            children: [
              TextField(key: const Key('first'), focusNode: first, maxLines: null),
              TextField(key: const Key('second'), focusNode: second),
              TextButton(onPressed: () => sent++, child: const Text('보내기')),
              const SizedBox(height: 400),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('first')));
    await tester.pump();
    expect(first.hasFocus, isTrue);
  }

  testWidgets('여러 줄 입력칸 밖 빈 곳(스크롤 목록 안)을 누르면 포커스가 풀린다', (tester) async {
    await pump(tester);

    await tester.tapAt(const Offset(400, 550));
    await tester.pump();

    expect(first.hasFocus, isFalse);
  });

  testWidgets('버튼을 누르면 버튼만 눌리고 키보드는 그대로다 — 채팅 "보내기" 뒤에도 이어서 친다', (tester) async {
    await pump(tester);

    await tester.tap(find.text('보내기'));
    await tester.pump();

    expect(sent, 1);
    expect(first.hasFocus, isTrue);
  });

  testWidgets('다른 입력칸을 누르면 그 칸으로 포커스가 옮겨 간다', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('second')));
    await tester.pump();

    expect(second.hasFocus, isTrue);
  });
}
