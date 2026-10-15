import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/profile/view/writing_example.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// "이렇게 적어요" 작성 예시(pen 마스터 `WritingExample`, 대장 전달 값).
void main() {
  const sentences = ['첫 번째 예시 문장이에요', '두 번째 예시 문장이에요'];

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: WritingExample(sentences: sentences)),
        ),
      ),
    );
  }

  Finder card(String sentence) => find.ancestor(of: find.text(sentence), matching: find.byType(Container)).first;

  testWidgets('캡션 "이렇게 적어요" 14/400 #3F3F3F', (tester) async {
    await pump(tester);

    final style = tester.widget<Text>(find.text('이렇게 적어요')).style!;
    expect((style.fontSize, style.fontWeight, style.color), (14, FontWeight.w400, AppColors.body));
  });

  testWidgets('문장마다 카드 하나 — #F7F7F7 · 모서리 12 · 안쪽 [12,14] · 폭을 채운다', (tester) async {
    await pump(tester);

    for (final sentence in sentences) {
      final box = tester.widget<Container>(card(sentence));
      final decoration = box.decoration! as BoxDecoration;
      expect((decoration.color, decoration.borderRadius), (AppColors.surfaceSoft, BorderRadius.circular(12)));
      expect(box.padding, const EdgeInsets.symmetric(vertical: 12, horizontal: 14));
      expect(tester.getSize(card(sentence)).width, 312);
    }
  });

  testWidgets('카드 사이 8', (tester) async {
    await pump(tester);

    expect(tester.getRect(card(sentences[1])).top - tester.getRect(card(sentences[0])).bottom, 8);
  });

  testWidgets('문장 14/400 · 줄높이 1.55 · #3F3F3F', (tester) async {
    await pump(tester);

    final style = tester.widget<Text>(find.text(sentences[0])).style!;
    expect((style.fontSize, style.fontWeight, style.height, style.color), (14, FontWeight.w400, 1.55, AppColors.body));
  });
}
