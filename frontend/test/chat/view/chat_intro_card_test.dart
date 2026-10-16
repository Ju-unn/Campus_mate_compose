import 'package:campus_mate/chat/view/chat_intro_card.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../billing/view/pretendard.dart';

/// 매칭 직후 첫 입장 안내 카드(pen 마스터 `cinKv` 접힘 · `TfPlG` 펼침 · 항목 `B3PzPm`, 화면 `PI7Kg` · `U6x9nV`).
/// 값은 대장이 준 pen 값표다(도우미는 pen 을 직접 열지 않는다). 좌표는 카드 왼쪽 위 기준.
void main() {
  const title = '대화를 시작하기 전에 알아 두세요';
  const summary = "48시간 안에 두 분이 모두 수락해야 카카오톡 아이디·실사진이 공개되고 대화가 이어져요. "
      "위쪽의 '수락하기'를 누르면 먼저 공개할 수 있어요.";
  const items = [
    "지금부터 48시간이 '신뢰 확인' 시간이에요. 서로 카카오톡 아이디와 실제 사진을 공개해도 좋은지 정하는 시간이에요.",
    "매칭 약 24시간 뒤, 아직 수락하지 않은 분께 알림이 가요. 알림을 누르거나 이 대화방에 들어오면 "
        "'카카오톡 아이디를 공유할까요?' 창이 떠요. 거기서 '수락하고 공유하기' 또는 '거절하고 나가기'를 고르면 돼요.",
    "기다리기 싫다면 지금 화면 위쪽의 '수락하기'를 눌러 보세요. 상대도 수락하면 바로 공개돼요. 수락은 취소할 수 없어요.",
    '48시간 안에 두 분이 모두 수락하지 않으면 이 대화는 종료돼요. 한쪽이 나가도 끝나요.',
    '공개된 뒤의 만남과 연락은 두 분의 선택이에요. 만나기 전에는 꼭 상대를 직접 확인하고 안전에 유의해 주세요. '
        '불편하면 신고·차단·나가기를 쓸 수 있어요.',
  ];

  setUpAll(loadPretendard);

  /// 접힘 상태는 부르는 쪽(채팅방 화면)이 들고 있다 — 여기서는 StatefulBuilder 가 그 자리다.
  Future<Rect> pump(
    WidgetTester tester, {
    bool expanded = false,
    double scale = 1,
    bool disableAnimations = false,
  }) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var isExpanded = expanded;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: 'Pretendard'),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(360, 780),
          textScaler: TextScaler.linear(scale),
          disableAnimations: disableAnimations,
        ),
        child: Scaffold(
          // 실제처럼 대화 목록(좌우 16, 세로 제한 없음) 안에 둔다.
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              StatefulBuilder(
                builder: (context, setState) => ChatIntroCard(
                  expanded: isExpanded,
                  onToggle: () => setState(() => isExpanded = !isExpanded),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    return tester.getRect(find.byType(ChatIntroCard));
  }

  Rect rectOf(WidgetTester tester, Finder finder, Rect card) => tester.getRect(finder).shift(-card.topLeft);

  Finder toggle() => find.byType(TextButton);

  TextStyle styleOf(WidgetTester tester, String text) => tester.widget<Text>(find.text(text)).style!;

  group('접힘(cinKv)', () {
    testWidgets('기본은 접힘 — 제목 · 요약 · "자세히 보기" 만 있고 항목은 없다', (tester) async {
      await pump(tester);

      expect(find.text(title), findsOneWidget);
      expect(find.text(summary), findsOneWidget);
      expect(find.text('자세히 보기'), findsOneWidget);
      expect(find.byIcon(AppIcons.chevronDown), findsOneWidget);
      for (final item in items) {
        expect(find.text(item), findsNothing);
      }
    });

    testWidgets('카드 — 폭 328(방 폭 − 좌우 16) · surface-strong · 모서리 14 · 그림자 없음', (tester) async {
      final card = await pump(tester);

      expect(card.width, 328);
      final box = find.descendant(of: find.byType(ChatIntroCard), matching: find.byType(DecoratedBox)).first;
      expect(tester.getRect(box), card);
      final decoration = tester.widget<DecoratedBox>(box).decoration as BoxDecoration;
      expect(decoration.color, AppColors.surfaceStrong);
      expect(decoration.borderRadius, BorderRadius.circular(14));
      expect(decoration.boxShadow, isNull);
      expect(find.descendant(of: find.byType(ChatIntroCard), matching: find.byType(Material)).evaluate().every(
            (element) => (element.widget as Material).elevation == 0,
          ), isTrue);
    });

    testWidgets('안쪽 여백 [16,16,4,16] · 세로 gap 8 · 토글 줄 높이 48', (tester) async {
      final card = await pump(tester);

      final titleRect = rectOf(tester, find.text(title), card);
      final summaryRect = rectOf(tester, find.text(summary), card);
      final toggleRect = rectOf(tester, toggle(), card);
      expect(titleRect.topLeft, const Offset(16, 16));
      expect(summaryRect.left, 16);
      expect(summaryRect.right, lessThanOrEqualTo(328 - 16));
      expect(summaryRect.top - titleRect.bottom, 8);
      expect(toggleRect.top - summaryRect.bottom, 8);
      expect(toggleRect.height, 48);
      expect(card.height - toggleRect.bottom, 4);
    });

    testWidgets('글자 — 제목 14/700 ink 1.5 · 요약 14/400 body 1.55 · 요약은 3줄 안', (tester) async {
      await pump(tester);

      final titleStyle = styleOf(tester, title);
      expect((titleStyle.fontSize, titleStyle.fontWeight, titleStyle.color, titleStyle.height), (14, FontWeight.w700, AppColors.ink, 1.5));
      final summaryStyle = styleOf(tester, summary);
      expect((summaryStyle.fontSize, summaryStyle.fontWeight, summaryStyle.color, summaryStyle.height), (14, FontWeight.w400, AppColors.body, 1.55));
      // 줄 수는 렌더로 잰다: 한 줄 14 × 1.55 = 21.7(Pretendard 렌더는 줄마다 22) — 4줄 높이 아래면 3줄 이하다.
      expect(tester.getSize(find.text(summary)).height, lessThan(4 * 14 * 1.55));
    });

    testWidgets('토글 — TextButton "자세히 보기" primary-text + chevron-down 16, 누르는 곳 48 이상', (tester) async {
      await pump(tester);

      expect(styleOf(tester, '자세히 보기').color, AppColors.primaryText);
      final chevron = tester.widget<Icon>(find.byIcon(AppIcons.chevronDown));
      expect((chevron.size, chevron.color), (16, AppColors.primaryText));
      // 아이콘은 글자 뒤(오른쪽)다.
      expect(tester.getCenter(find.byIcon(AppIcons.chevronDown)).dx, greaterThan(tester.getCenter(find.text('자세히 보기')).dx));
      final size = tester.getSize(toggle());
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
    });

    for (final expanded in [false, true]) {
      final label = expanded ? '접기' : '자세히 보기';
      final icon = expanded ? AppIcons.chevronUp : AppIcons.chevronDown;
      testWidgets('토글 줄(pen 296×48) "$label" — 오른쪽 정렬 · 세로 가운데 · 버튼 왼쪽 12 · 글자 → chevron 4 · chevron 끝 = 카드 오른쪽 안쪽 16', (tester) async {
        final card = await pump(tester, expanded: expanded);

        final button = rectOf(tester, toggle(), card);
        final text = rectOf(tester, find.text(label), card);
        final chevron = rectOf(tester, find.byIcon(icon), card);
        final labelStyle = styleOf(tester, label);
        expect((labelStyle.fontSize, labelStyle.fontWeight, labelStyle.color), (14, FontWeight.w600, AppColors.primaryText));
        expect(chevron.right, 328 - 16);
        // chevron 은 pen 에서 버튼 밖이지만 앱은 같이 눌리게 버튼 안에 둔다(대장 지시) — 버튼 오른쪽 끝 = chevron 오른쪽 끝.
        expect(button.right, chevron.right);
        expect(chevron.left - text.right, 4);
        expect(text.left - button.left, 12);
        expect(button.height, 48);
        expect(text.center.dy, moreOrLessEquals(button.center.dy, epsilon: 0.5));
        expect(chevron.center.dy, moreOrLessEquals(button.center.dy, epsilon: 0.5));
        expect(button.width, greaterThanOrEqualTo(48));
      });
    }
  });

  group('펼침(TfPlG)', () {
    testWidgets('"자세히 보기" → 항목 5개(글자 그대로) + "접기" chevron-up → 다시 접힘', (tester) async {
      await pump(tester);

      await tester.tap(find.text('자세히 보기'));
      await tester.pumpAndSettle();

      expect(find.text(summary), findsNothing);
      for (var index = 0; index < items.length; index++) {
        expect(find.text(items[index]), findsOneWidget, reason: '항목 ${index + 1}');
        expect(find.text('${index + 1}.'), findsOneWidget);
      }
      expect(find.text('접기'), findsOneWidget);
      expect(find.byIcon(AppIcons.chevronUp), findsOneWidget);
      expect(find.byIcon(AppIcons.chevronDown), findsNothing);

      await tester.tap(find.text('접기'));
      await tester.pumpAndSettle();

      expect(find.text(summary), findsOneWidget);
      expect(find.text(items.first), findsNothing);
      expect(find.text('자세히 보기'), findsOneWidget);
    });

    testWidgets('항목(B3PzPm) — 번호 칸 20 · 14/700 ink, 본문 14/400 body 1.55, 가로 gap 6, 항목 사이 8', (tester) async {
      final card = await pump(tester, expanded: true);

      final titleRect = rectOf(tester, find.text(title), card);
      final first = rectOf(tester, find.text(items.first), card);
      expect(first.top - titleRect.bottom, 8);
      for (var index = 0; index < items.length; index++) {
        final number = rectOf(tester, find.text('${index + 1}.'), card);
        final body = rectOf(tester, find.text(items[index]), card);
        expect(number.left, 16, reason: '항목 ${index + 1}');
        // 번호 칸 폭 20 + 가로 gap 6 = 본문은 번호 칸 왼쪽에서 26.
        expect(body.left - number.left, 26, reason: '항목 ${index + 1}');
        expect(body.right, lessThanOrEqualTo(328 - 16));
        expect(body.top, number.top);
        final numberStyle = styleOf(tester, '${index + 1}.');
        expect((numberStyle.fontSize, numberStyle.fontWeight, numberStyle.color), (14, FontWeight.w700, AppColors.ink));
        final bodyStyle = styleOf(tester, items[index]);
        expect((bodyStyle.fontSize, bodyStyle.fontWeight, bodyStyle.color, bodyStyle.height), (14, FontWeight.w400, AppColors.body, 1.55));
        if (index > 0) {
          final above = rectOf(tester, find.text(items[index - 1]), card);
          expect(body.top - above.bottom, 8, reason: '항목 $index → ${index + 1}');
        }
      }
      final toggleRect = rectOf(tester, toggle(), card);
      expect(toggleRect.top - rectOf(tester, find.text(items.last), card).bottom, 8);
      expect(toggleRect.height, 48);
      expect(card.height - toggleRect.bottom, 4);
    });
  });

  group('접근성', () {
    testWidgets('토글은 버튼이고 펼침 상태를 알린다', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);

      expect(
        tester.getSemantics(toggle()),
        isSemantics(label: '자세히 보기', isButton: true, hasTapAction: true, hasExpandedState: true, isExpanded: false),
      );

      await tester.tap(toggle());
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(toggle()),
        isSemantics(label: '접기', isButton: true, hasTapAction: true, hasExpandedState: true, isExpanded: true),
      );
      semantics.dispose();
    });

    testWidgets('카드 전체는 읽기용 묶음 하나다(제목 · 본문이 같은 그룹)', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);

      final group = tester.getSemantics(find.byType(ChatIntroCard));
      final titleNode = tester.getSemantics(find.text(title));
      final summaryNode = tester.getSemantics(find.text(summary));
      bool isInside(SemanticsNode node) {
        for (SemanticsNode? parent = node; parent != null; parent = parent.parent) {
          if (parent == group) {
            return true;
          }
        }
        return false;
      }

      expect(isInside(titleNode), isTrue);
      expect(isInside(summaryNode), isTrue);
      semantics.dispose();
    });

    for (final scale in [1.3, 2.0]) {
      for (final expanded in [false, true]) {
        testWidgets('글자 배율 $scale · ${expanded ? '펼침' : '접힘'} — 넘치거나 잘리는 글자가 없고 토글 줄은 48 이상', (tester) async {
          await pump(tester, scale: scale, expanded: expanded);

          expect(tester.takeException(), isNull);
          for (final paragraph in tester.renderObjectList<RenderParagraph>(
              find.descendant(of: find.byType(ChatIntroCard), matching: find.byType(RichText)))) {
            expect(paragraph.didExceedMaxLines, isFalse, reason: paragraph.text.toPlainText());
            expect(paragraph.getMaxIntrinsicHeight(paragraph.size.width), lessThanOrEqualTo(paragraph.size.height + 0.5),
                reason: paragraph.text.toPlainText());
          }
          expect(tester.getSize(toggle()).height, greaterThanOrEqualTo(48));
          if (expanded) {
            // 번호 칸(배율 1 에서 20)이 글자와 같이 커진다 — "5." 가 "5" / "." 두 줄로 쪼개지지 않는다.
            for (var index = 1; index <= items.length; index++) {
              // 두 줄 높이(14 × 배율 × 1.55 × 2) 아래면 한 줄이다.
              expect(tester.getSize(find.text('$index.')).height, lessThan(2 * 14 * scale * 1.55), reason: '$index.');
            }
          }
        });
      }
    }
  });

  group('모션', () {
    testWidgets('높이는 {motion.standard} 220ms · easeOutCubic 으로 바뀌고 끝까지 가라앉는다', (tester) async {
      await pump(tester);

      final animated = tester.widget<AnimatedSize>(find.byType(AnimatedSize));
      expect((animated.duration, animated.curve), (AppMotion.standard, AppMotion.standardCurve));
      final before = tester.getSize(find.byType(ChatIntroCard)).height;

      await tester.tap(find.text('자세히 보기'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));
      final middle = tester.getSize(find.byType(ChatIntroCard)).height;
      await tester.pumpAndSettle();
      final after = tester.getSize(find.byType(ChatIntroCard)).height;

      expect(middle, greaterThan(before));
      expect(middle, lessThan(after));
    });

    testWidgets('동작 줄이기면 애니메이션 없이 바로 펼친다', (tester) async {
      await pump(tester, disableAnimations: true);

      expect(find.byType(AnimatedSize), findsNothing);
      await tester.tap(find.text('자세히 보기'));
      await tester.pump();

      // 첫 프레임에 이미 다 펼친 높이다(버튼 잉크는 따로 움직이니 높이만 본다).
      expect(find.text(items.last), findsOneWidget);
      final first = tester.getSize(find.byType(ChatIntroCard)).height;
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(ChatIntroCard)).height, first);
    });
  });
}
