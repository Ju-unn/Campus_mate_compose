import 'package:campus_mate/chat/view/chat_input_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('보내기 버튼의 눌림 효과는 화면이 아니라 버튼이 그린다(§4-2)', (tester) async {
    // `InkWell` 은 가장 가까운 Material 에 그린다 — 그게 Scaffold 면 키보드가 올라와 입력 바가
    // 움직여도 눌림 테두리가 제자리에 남아 공중에 뜬다(실기기 2026-09-27).
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            const Spacer(),
            ChatInputBar(onSend: (_) {}, isSending: false),
          ],
        ),
      ),
    ));

    final button = find.descendant(of: find.byType(ChatInputBar), matching: find.byType(InkWell));
    final painter = find.ancestor(of: button, matching: find.byType(Material)).first;

    expect(tester.getSize(painter), const Size(40, 40));
  });
}
