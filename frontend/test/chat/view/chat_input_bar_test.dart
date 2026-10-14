import 'package:campus_mate/chat/view/chat_input_bar.dart';
import 'package:campus_mate/common/widgets/keyboard_dismiss_on_tap.dart';
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

    // 15c 자기소개: 앱 상한(300)보다 긴 옛 글(서버 1000자 시절)을 열었을 때. 지우면 앞 max 로 잘려 뒤가 사라지면 안 된다.
    group('이미 상한을 넘긴 글', () {
      test('한 글자를 지우면 그대로 지워진다 — 뒤를 잘라 내지 않는다', () {
        expect(apply(3, '가나다라마', '가나다라').text, '가나다라');
      });

      test('더 치면 입력을 무시한다', () {
        expect(apply(3, '가나다라마', '가나다라마바').text, '가나다라마');
      });

      test('고른 글을 더 긴 글로 바꿔 넣어도 막는다 — 뒤를 잘라 내지 않는다', () {
        const old = TextEditingValue(text: '가나다라마', selection: TextSelection(baseOffset: 0, extentOffset: 1));
        final result = codePointLimitFormatter(3).formatEditUpdate(
          old,
          const TextEditingValue(text: '바사나다라마', selection: TextSelection.collapsed(offset: 2)),
        );
        expect(result, old);
      });
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

  // 앱 전체를 감싼 KeyboardDismissOnTap(PR #523) 아래에서 — 꺼진 버튼이 탭을 안 받으면 탭이 바깥으로 넘어가 키보드가 내려간다.
  group('꺼진 보내기 버튼', () {
    var sent = 0;
    Finder sendButton() => find.descendant(of: find.byType(ChatInputBar), matching: find.byType(InkWell));

    Future<void> pump(WidgetTester tester) async {
      sent = 0;
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => KeyboardDismissOnTap(child: child!),
        home: Scaffold(
          body: Column(
            children: [
              const Spacer(),
              ChatInputBar(
                onSend: (_) async {
                  sent++;
                  return true;
                },
                isSending: false,
              ),
            ],
          ),
        ),
      ));
    }

    testWidgets('글이 비어 꺼진 보내기를 눌러도 입력칸 포커스(키보드)가 그대로고 보내지 않는다', (tester) async {
      await pump(tester);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      final focus = tester.widget<EditableText>(find.byType(EditableText)).focusNode;
      expect(focus.hasFocus, isTrue);

      await tester.tap(sendButton());
      await tester.pump();

      expect(focus.hasFocus, isTrue);
      expect(sent, 0);
    });

    testWidgets('화면 읽기에는 꺼진 "보내기" 버튼으로 남는다 — 누를 수 있는 동작이 없다', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);

      expect(
        tester.getSemantics(sendButton()),
        matchesSemantics(label: '보내기', isButton: true, hasEnabledState: true, isEnabled: false),
      );
      semantics.dispose();
    });

    testWidgets('글을 쓰면 켜진 버튼이고 누르면 보낸다 — 포커스는 그대로다', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      await tester.enterText(find.byType(TextField), '안녕');
      await tester.pump();
      final focus = tester.widget<EditableText>(find.byType(EditableText)).focusNode;

      expect(
        tester.getSemantics(sendButton()),
        matchesSemantics(
          label: '보내기',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(sendButton());
      await tester.pump();

      expect(sent, 1);
      expect(focus.hasFocus, isTrue);
      semantics.dispose();
    });
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
