import 'package:campus_mate/community/view/vote_option.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 입력 칸(pen `xlCc2` · `k9Bdo8`, 158 × 72)의 세로 배치와 한 줄 입력.
/// 테스트 기본 글꼴(Ahem)은 글자 폭이 달라 줄바꿈 시험이 의미 없다 — 실제 글꼴 Pretendard 를 올려서 잰다.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loader = FontLoader('Pretendard')
      ..addFont(rootBundle.load('assets/fonts/Pretendard-Medium.otf'))
      ..addFont(rootBundle.load('assets/fonts/Pretendard-Bold.otf'));
    await loader.load();
  });

  const key = Key('field');

  Future<TextEditingController> pump(WidgetTester tester, {double scale = 1.0, String text = '가나다라마바'}) async {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final controller = TextEditingController(text: text);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 158,
              child: VoteOption.input(
                side: VoteSide.agree,
                controller: controller,
                hint: '보기 1',
                fieldKey: key,
                inputFormatters: [LengthLimitingTextInputFormatter(6)],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return controller;
  }

  /// 입력칸에 그려진 글자 줄들의 칸 기준 위치(화면 좌표 − 칸 위).
  List<Rect> lines(WidgetTester tester, int length) {
    final editable = tester.state<EditableTextState>(find.byType(EditableText)).renderEditable;
    final top = tester.getTopLeft(find.byType(VoteOption)).dy;
    return [
      for (final box in editable.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: length)))
        box.toRect().shift(editable.localToGlobal(Offset.zero)).shift(Offset(0, -top)),
    ];
  }

  Rect underline(WidgetTester tester) {
    final rect = tester.getRect(find.byKey(VoteOption.underlineKey));
    return rect.shift(Offset(0, -tester.getTopLeft(find.byType(VoteOption)).dy));
  }

  testWidgets('배율 1.0: 글자 줄 중심이 칸 위에서 32 · 밑줄 윗선이 50(글자 줄 24 · 간격 6 · 밑줄 2 가 가운데)', (tester) async {
    await pump(tester);
    final text = lines(tester, 6).single;
    expect(text.center.dy, closeTo(32, 0.5));
    expect(underline(tester).top, closeTo(50, 0.01));
    expect(underline(tester).height, 2);
  });

  testWidgets('글자를 키워도(1.3) 6자가 한 줄이고, 밑줄은 글자 줄 아래 6(± 0.5) 이상 떨어진다', (tester) async {
    await pump(tester, scale: 1.3);
    expect(tester.takeException(), isNull);
    final boxes = lines(tester, 6);
    expect(boxes, hasLength(1), reason: '두 줄로 꺾였다: $boxes');
    // 글자 줄 높이는 글꼴 지표로 반올림돼 실제 줄이 계산(20×1.15×1.2)보다 0.2 안팎 크다 — 간격 6 에서 0.5 까지 허용.
    expect(underline(tester).top, closeTo(boxes.single.bottom + 6, 0.5));
    expect(underline(tester).bottom, lessThanOrEqualTo(72));
  });

  testWidgets('글자 2배에서도 6자가 한 줄이고 칸(72) 안에 있다 — 입력칸 글자 배율은 1.15 까지만', (tester) async {
    await pump(tester, scale: 2.0);
    final boxes = lines(tester, 6);
    expect(boxes, hasLength(1));
    expect(boxes.single.top, greaterThanOrEqualTo(0));
    expect(boxes.single.bottom, lessThanOrEqualTo(underline(tester).top));
    expect(underline(tester).top, closeTo(boxes.single.bottom + 6, 0.5)); // 배율 상한(1.15)을 textHeight 계산에서 빼면 어긋난다
    expect(underline(tester).bottom, lessThanOrEqualTo(72));
    // 20px 글자가 2.0 배가 아니라 1.15 배(= 23)로 그려진다.
    expect(tester.state<EditableTextState>(find.byType(EditableText)).renderEditable.textScaler.scale(20), closeTo(23, 0.01));
  });

  testWidgets('줄바꿈은 넣을 수 없다 — Enter 는 "완료", 붙여 넣은 줄바꿈은 지워진다', (tester) async {
    final controller = await pump(tester, text: '');
    final field = tester.widget<TextField>(find.byKey(key));
    expect(field.textInputAction, TextInputAction.done);
    expect(field.keyboardType, TextInputType.text);

    await tester.enterText(find.byKey(key), '가\n나');
    expect(controller.text, '가나');
    await tester.enterText(find.byKey(key), '다\r\n라');
    expect(controller.text, '다라');
  });

  testWidgets('글자 선택 색은 흰색 반투명 — 파랑·빨강 칸에서 기본 테마색과 겹치지 않는다', (tester) async {
    await pump(tester);
    final theme = TextSelectionTheme.of(tester.element(find.byType(EditableText)));
    expect(theme.selectionColor, Colors.white.withValues(alpha: 0.4));
    expect(theme.selectionHandleColor, Colors.white);
    expect(theme.cursorColor, Colors.white);
  });
}
