import 'package:campus_mate/chat/view/chat_input_bar.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 입력 바의 1,000자 동작은 chat_room_screen_test 의 백로그 21 묶음이 지킨다. 여기서는 신고 시트(200자)도
  // 같은 함수를 쓰게 공개한 상한 인자만 본다.
  group('codePointLimitFormatter', () {
    TextEditingValue apply(int max, String oldText, String newText) {
      return codePointLimitFormatter(max).formatEditUpdate(
        TextEditingValue(text: oldText, selection: TextSelection.collapsed(offset: oldText.length)),
        TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: newText.length)),
      );
    }

    test('상한 안이면 그대로 둔다', () {
      expect(apply(5, '', '가나다').text, '가나다');
    });

    test('넘치면 앞 max 코드포인트로 자른다 — 합성 이모지는 코드포인트 여러 개로 센다', () {
      const family = '👨‍👩‍👧'; // 보이는 글자 1개, 코드포인트 5개
      final result = apply(7, '', '가나$family가');

      expect(result.text.runes.length, 7);
      expect(result.text, '가나$family');
    });

    test('이미 가득 찬 글에 더 넣으면 입력을 무시한다', () {
      expect(apply(3, '가나다', '가나다라').text, '가나다');
    });
  });

  testWidgets('보내기 버튼의 눌림 효과는 화면이 아니라 버튼이 그린다(§4-2)', (tester) async {
    // `InkWell` 은 가장 가까운 Material 에 그린다 — 그게 Scaffold 면 키보드가 올라와 입력 바가
    // 움직여도 눌림 테두리가 제자리에 남아 공중에 뜬다(실기기 2026-09-27).
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            const Spacer(),
            ChatInputBar(onSend: (_) async => true, isSending: false),
          ],
        ),
      ),
    ));

    final button = find.descendant(of: find.byType(ChatInputBar), matching: find.byType(InkWell));
    final painter = find.ancestor(of: button, matching: find.byType(Material)).first;

    expect(tester.getSize(painter), const Size(40, 40));
  });

  group('pen JgryI 값', () {
    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Spacer(),
              ChatInputBar(onSend: (_) async => true, isSending: false),
            ],
          ),
        ),
      ));
    }

    testWidgets('바 위쪽 선 #DDDDDD 1 · 안쪽 [10,16,14,16](대장 Q4 인스턴스 값) · 칸 48 · 칸↔버튼 8', (tester) async {
      await pump(tester);

      final bar = tester.getRect(find.byType(ChatInputBar));
      final container = tester.widget<Container>(
        find.descendant(of: find.byType(ChatInputBar), matching: find.byType(Container)).first,
      );
      expect(container.color, AppColors.canvas);
      expect(
        (container.foregroundDecoration! as BoxDecoration).border,
        const Border(top: BorderSide(color: AppColors.hairline)),
      );
      final field = tester.getRect(find.byType(TextField));
      expect(field.height, 48);
      // 위 선 1 은 안쪽 여백 안에 그린다(pen stroke inside).
      expect((field.left - bar.left, field.top - bar.top, bar.bottom - field.bottom), (16, 10, 14));
      final send = find.descendant(of: find.byType(ChatInputBar), matching: find.byType(InkWell));
      expect((tester.getRect(send).left - field.right, bar.right - tester.getRect(send).right), (8, 16));
    });

    testWidgets('칸 모서리 22 · #F7F7F7, placeholder n1UArl 16 muted', (tester) async {
      await pump(tester);

      final decoration = tester.widget<TextField>(find.byType(TextField)).decoration!;
      expect(decoration.fillColor, AppColors.surfaceSoft);
      expect((decoration.border! as OutlineInputBorder).borderRadius, BorderRadius.circular(22));
      expect((decoration.hintStyle!.fontSize, decoration.hintStyle!.color), (16, AppColors.muted));
      // 글자를 키워도 안내 문구가 두 줄로 접혀 빈 칸이 커지지 않게 한 줄로 자른다(검토 권고 1).
      expect(tester.widget<Text>(find.text('메시지를 입력하세요')).maxLines, 1);
    });
  });
}
