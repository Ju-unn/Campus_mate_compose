import 'package:campus_mate/community/view/poll_donut.dart';
import 'package:campus_mate/community/view/vote_option.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// pen 마스터(컴포넌트 구역 `Z54et`): VoteOption · O `g6Cxp` · X `fmSNT` · Input Blue `xlCc2` · Input Red `k9Bdo8`.
void main() {
  Future<void> pump(WidgetTester tester, Widget option, {double width = 144}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: SizedBox(width: width, child: option))),
      ),
    );
  }

  BoxDecoration boxDecoration(WidgetTester tester) {
    final box = tester.widget<DecoratedBox>(find.descendant(of: find.byType(VoteOption), matching: find.byType(DecoratedBox)).first);
    return box.decoration as BoxDecoration;
  }

  Color? fill(WidgetTester tester) {
    final button = find.byType(FilledButton);
    if (button.evaluate().isNotEmpty) return tester.widget<FilledButton>(button).style!.backgroundColor!.resolve({});
    final box = tester.widget<DecoratedBox>(find.descendant(of: find.byType(VoteOption), matching: find.byType(DecoratedBox)).first);
    return (box.decoration as BoxDecoration).color;
  }

  testWidgets('O 칸(g6Cxp): 파랑 · 높이 72 · 모서리 8 · 흰 원 34', (tester) async {
    await pump(tester, const VoteOption.mark(side: VoteSide.agree, semanticLabel: '찬성'));
    expect(fill(tester), pollAgreeBlue);
    expect(pollAgreeBlue, const Color(0xFF2D96DE));
    expect(tester.getSize(find.byType(VoteOption)).height, 72);
    final icon = tester.widget<Icon>(find.byIcon(AppIcons.circle));
    expect((icon.size, icon.color), (34.0, const Color(0xFFFFFFFF)));
    expect(find.bySemanticsLabel('찬성'), findsOneWidget);
  });

  testWidgets('X 칸(fmSNT): 빨강 #FF385C · 높이 72 · 흰 x 34', (tester) async {
    await pump(tester, const VoteOption.mark(side: VoteSide.disagree, semanticLabel: '반대'));
    expect(fill(tester), AppColors.primary);
    expect(tester.getSize(find.byType(VoteOption)).height, 72);
    final icon = tester.widget<Icon>(find.byIcon(AppIcons.x));
    expect((icon.size, icon.color), (34.0, const Color(0xFFFFFFFF)));
  });

  testWidgets('누르지 않는 칸(질문 작성의 미리보기)은 버튼이 아니다', (tester) async {
    await pump(tester, const VoteOption.mark(side: VoteSide.agree, interactive: false));
    expect(find.byType(FilledButton), findsNothing);
    expect(fill(tester), pollAgreeBlue);
  });

  testWidgets('글자 칸(PollCard 직접 적기): 파랑·빨강 · 72 · 흰 20/700 · 밑줄 없음', (tester) async {
    await pump(tester, VoteOption.text(side: VoteSide.agree, label: '짜장', onPressed: () {}));
    expect(fill(tester), pollAgreeBlue);
    expect(tester.getSize(find.byType(VoteOption)).height, 72);
    final style = tester.widget<Text>(find.text('짜장')).style!;
    expect((style.fontSize, style.fontWeight, style.color), (20.0, FontWeight.w700, const Color(0xFFFFFFFF)));
    expect(find.byType(Divider), findsNothing);

    await pump(tester, VoteOption.text(side: VoteSide.disagree, label: '짬뽕', onPressed: () {}));
    expect(fill(tester), AppColors.primary);
  });

  testWidgets('글자 칸: 6자가 폭 144 안에 줄바꿈 없이 들어가고, 좌우 안쪽은 정확히 8', (tester) async {
    await pump(tester, VoteOption.text(side: VoteSide.agree, label: '가나다라마바', onPressed: () {}));
    final box = tester.getRect(find.byType(VoteOption));
    final label = tester.getRect(find.text('가나다라마바'));
    expect(box.width, 144);
    expect(label.width, lessThanOrEqualTo(144 - 16));
    expect(label.height, lessThan(30)); // 두 줄이면 40 이 넘는다
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.style!.padding!.resolve({}), const EdgeInsets.symmetric(horizontal: 8)); // 마스터 padding [0,8]
  });

  testWidgets('글자 칸: 글자가 칸보다 커지면 안쪽 8 만 남기고 가득 줄여 맞춘다(좌우 정확히 8)', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester, VoteOption.text(side: VoteSide.agree, label: '가나다라마바', onPressed: () {}));
    final box = tester.getRect(find.byType(VoteOption));
    final label = tester.getRect(find.text('가나다라마바'));
    expect(label.left - box.left, closeTo(8, 0.01));
    expect(box.right - label.right, closeTo(8, 0.01));
  });

  testWidgets('모서리는 정확히 8(마스터 g6Cxp · fmSNT · xlCc2 · k9Bdo8) — 누르는 칸 · 그냥 칸 · 입력 칸 모두', (tester) async {
    final eight = BorderRadius.circular(8);
    await pump(tester, const VoteOption.mark(side: VoteSide.agree));
    final shape = tester.widget<FilledButton>(find.byType(FilledButton)).style!.shape!.resolve({}) as RoundedRectangleBorder;
    expect(shape.borderRadius, eight);

    await pump(tester, const VoteOption.mark(side: VoteSide.agree, interactive: false));
    expect(boxDecoration(tester).borderRadius, eight);

    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pump(tester, VoteOption.input(side: VoteSide.disagree, controller: controller, hint: '보기 2'));
    expect(boxDecoration(tester).borderRadius, eight);
  });

  testWidgets('투표 중이라 꺼진 칸도 색이 남는다 — 파랑/빨강 반투명 + 흰 아이콘 · 글자(깜빡임 방지)', (tester) async {
    for (final (option, color) in [
      (const VoteOption.mark(side: VoteSide.agree), pollAgreeBlue),
      (const VoteOption.text(side: VoteSide.disagree, label: '짬뽕'), AppColors.primary),
    ]) {
      await pump(tester, option);
      final style = tester.widget<FilledButton>(find.byType(FilledButton)).style!;
      expect(style.backgroundColor!.resolve({WidgetState.disabled}), color.withValues(alpha: 0.5));
      expect(style.foregroundColor!.resolve({WidgetState.disabled}), AppColors.onPrimary);
    }
  });

  testWidgets('글자 칸: 글자를 키워도 줄바꿈 없이 칸 안으로 줄여 맞춘다', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester, VoteOption.text(side: VoteSide.agree, label: '가나다라마바', onPressed: () {}));
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.text('가나다라마바')).width, lessThanOrEqualTo(144 - 16));
    expect(tester.getSize(find.byType(VoteOption)).height, 72);
  });

  testWidgets('글자 칸을 누르면 onPressed, 못 누르는 중이면(null) 꺼진다', (tester) async {
    var taps = 0;
    await pump(tester, VoteOption.text(side: VoteSide.agree, label: '짜장', onPressed: () => taps++));
    await tester.tap(find.text('짜장'));
    expect(taps, 1);
    await pump(tester, const VoteOption.text(side: VoteSide.agree, label: '짜장'));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });

  group('입력 칸(xlCc2 · k9Bdo8)', () {
    testWidgets('파랑·빨강 · 높이 72 · 안쪽 16 · 흰 20/700 글자 · 흰 2px 밑줄', (tester) async {
      final controller = TextEditingController(text: '짜장');
      addTearDown(controller.dispose);
      await pump(tester, VoteOption.input(side: VoteSide.agree, controller: controller, hint: '보기 1'), width: 158);
      expect(fill(tester), pollAgreeBlue);
      final box = tester.getRect(find.byType(VoteOption));
      expect(box.size, const Size(158, 72));
      final style = tester.widget<TextField>(find.byType(TextField)).style!;
      expect((style.fontSize, style.fontWeight, style.color), (20.0, FontWeight.w700, const Color(0xFFFFFFFF)));
      final underline = tester.getRect(find.byKey(VoteOption.underlineKey));
      expect(underline.height, 2);
      expect(underline.left - box.left, 16);
      expect(box.right - underline.right, 16);
      expect(tester.widget<ColoredBox>(find.byKey(VoteOption.underlineKey)).color, const Color(0xFFFFFFFF));
    });

    testWidgets('칸 어디를 눌러도 글자 입력이 시작되고, 누르는 곳은 48 이상이다', (tester) async {
      final handle = tester.ensureSemantics();
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pump(tester, VoteOption.input(side: VoteSide.agree, controller: controller, hint: '보기 1'), width: 158);
      final box = tester.getRect(find.byType(VoteOption));
      // 글자 줄(24)이 아니라 칸 아래쪽 · 가장자리를 눌러도 입력칸이 받는다.
      for (final point in [box.bottomLeft + const Offset(4, -4), box.topRight + const Offset(-4, 4), box.center]) {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        await tester.tapAt(point);
        await tester.pump();
        expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue, reason: '$point');
      }
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose(); // 시험이 끝나기 전에 닫아야 한다(addTearDown 은 검사보다 늦다)
    });

    testWidgets('빨강 칸은 #FF385C, 비어 있으면 흰 안내 글("보기 2")이 보인다', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pump(tester, VoteOption.input(side: VoteSide.disagree, controller: controller, hint: '보기 2'));
      expect(fill(tester), AppColors.primary);
      expect(find.text('보기 2'), findsOneWidget);
    });

    testWidgets('입력칸에 키와 입력 제한(inputFormatters)을 그대로 넘긴다', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      const key = Key('field');
      await pump(
        tester,
        VoteOption.input(
          side: VoteSide.agree,
          controller: controller,
          hint: '보기 1',
          fieldKey: key,
          inputFormatters: [LengthLimitingTextInputFormatter(3)],
        ),
      );
      await tester.enterText(find.byKey(key), '가나다라마');
      expect(controller.text, '가나다');
    });
  });
}
