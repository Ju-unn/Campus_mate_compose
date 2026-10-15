import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/tour/view/coach_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int nexts;
  late int skips;

  Future<void> pump(WidgetTester tester, {bool isLast = false, double textScale = 1, Widget? detail}) async {
    nexts = 0;
    skips = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: const Size(360, 740), textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: SizedBox(
                width: 312,
                child: CoachBubble(
                  number: 2,
                  total: 6,
                  title: '프로필부터 채워 보세요',
                  body: '사진, 소개, 이상형을 채우면 더 잘 맞아요.',
                  isLast: isLast,
                  detail: detail,
                  onNext: () => nexts++,
                  onSkip: () => skips++,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  TextStyle styleOf(WidgetTester tester, String text) => tester.renderObject<RenderParagraph>(find.text(text)).text.style!;
  Rect rectOf(WidgetTester tester, Finder finder) => tester.getRect(finder);
  Finder skip() => find.byKey(CoachBubble.skipKey);
  Finder next() => find.descendant(of: find.byType(CoachBubble), matching: find.byType(AppButton));

  testWidgets('pen gfoSM — 흰 바탕 · 모서리 16 · 폭은 부모가 준 312', (tester) async {
    await pump(tester);

    final material = tester.widget<Material>(
      find.descendant(of: find.byType(CoachBubble), matching: find.byType(Material)).first,
    );
    expect(material.color, AppColors.canvas);
    expect(material.borderRadius, BorderRadius.circular(AppRadius.card));
    expect(tester.getSize(find.byType(CoachBubble)).width, 312);
  });

  testWidgets('글자 — 단계 12/600 muted · 제목 16/700 ink · 설명 14/400 ink', (tester) async {
    await pump(tester);

    final step = styleOf(tester, '2 / 6');
    expect((step.fontSize, step.fontWeight, step.color), (12, FontWeight.w600, AppColors.muted));
    final title = styleOf(tester, '프로필부터 채워 보세요');
    expect((title.fontSize, title.fontWeight, title.color), (16, FontWeight.w700, AppColors.ink));
    final body = styleOf(tester, '사진, 소개, 이상형을 채우면 더 잘 맞아요.');
    expect((body.fontSize, body.fontWeight, body.color), (14, FontWeight.w400, AppColors.ink));
  });

  testWidgets('안쪽 여백 위 16 · 좌우 16 · 아래 12, 단계 → 제목 → 설명 → 버튼 줄 사이 8', (tester) async {
    await pump(tester);

    final bubble = rectOf(tester, find.byType(CoachBubble));
    final step = rectOf(tester, find.text('2 / 6'));
    final title = rectOf(tester, find.text('프로필부터 채워 보세요'));
    final body = rectOf(tester, find.text('사진, 소개, 이상형을 채우면 더 잘 맞아요.'));
    final footer = rectOf(tester, next());
    expect((step.left, step.top), (bubble.left + 16, bubble.top + 16));
    expect(title.top, step.bottom + 8);
    expect(body.top, title.bottom + 8);
    expect(footer.top, body.bottom + 8);
    expect(footer.bottom, bubble.bottom - 12);
    expect(footer.right, bubble.right - 16);
  });

  testWidgets('버튼 줄(높이 48) — 왼쪽 끝 "건너뛰기"(76×48 · 글자 왼쪽 12), 오른쪽 끝 "다음"(104×48), 누르면 각각 부른다', (tester) async {
    await pump(tester);

    final bubble = rectOf(tester, find.byType(CoachBubble));
    final skipBox = rectOf(tester, skip());
    final nextBox = rectOf(tester, next());
    expect(skipBox.size, const Size(76, 48));
    expect(nextBox.size, const Size(104, 48));
    expect(skipBox.left, bubble.left + 16);
    expect(skipBox.top, nextBox.top);
    expect(rectOf(tester, find.text('건너뛰기')).left, skipBox.left + 12);
    // 터치 영역 48 이상(DESIGN §11).
    expect(skipBox.height, greaterThanOrEqualTo(48));
    expect(skipBox.width, greaterThanOrEqualTo(48));

    await tester.tap(find.text('다음'));
    await tester.tap(find.text('건너뛰기'));
    expect((nexts, skips), (1, 1));
  });

  testWidgets('마지막 장 — 버튼은 "시작하기", 건너뛰기는 안 보이고 눌리지 않지만 자리는 그대로', (tester) async {
    await pump(tester);
    final before = tester.getSize(find.byType(CoachBubble));
    final skipSlot = tester.getSize(skip());

    await pump(tester, isLast: true);

    expect(find.widgetWithText(AppButton, '시작하기'), findsOneWidget);
    expect(find.text('건너뛰기').hitTestable(), findsNothing);
    expect(tester.getSize(skip()), skipSlot);
    expect(tester.getSize(find.byType(CoachBubble)), before);
  });

  testWidgets('설명 아래 8 에 [detail](5단계 정밀 분석 항목)을 붙이고, 버튼 줄은 그 아래 8', (tester) async {
    await pump(tester, detail: const Text('성향 9가지 비교'));

    final body = rectOf(tester, find.text('사진, 소개, 이상형을 채우면 더 잘 맞아요.'));
    final detail = rectOf(tester, find.text('성향 9가지 비교'));
    expect(detail.top, body.bottom + 8);
    expect(rectOf(tester, next()).top, detail.bottom + 8);
  });

  testWidgets('스크린리더 — 단계는 "6단계 중 2단계", 제목은 머리글', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    expect(find.bySemanticsLabel('6단계 중 2단계'), findsOneWidget);
    expect(tester.getSemantics(find.text('프로필부터 채워 보세요')), isSemantics(isHeader: true));
    handle.dispose();
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('글자 배율 $scale 에서도 넘치지 않고 버튼 글자가 한 줄이다', (tester) async {
      await pump(tester, isLast: true, textScale: scale);

      expect(tester.takeException(), isNull);
      for (final label in ['시작하기', '건너뛰기']) {
        final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
        expect(paragraph.size.height, lessThan(paragraph.text.style!.fontSize! * scale * 2), reason: label);
      }
    });
  }
}
