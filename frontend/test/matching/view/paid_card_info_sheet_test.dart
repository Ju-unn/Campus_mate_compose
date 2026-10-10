import 'dart:io';

import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/matching/view/paid_card_info_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// "이렇게 정밀하게 골랐어요" 안내 시트(pen `EP8pA` → 시트 `sp1xa`, 값표 §6)를 pen 값과 대조한다.
/// 문구는 pen 값표 그대로다 — 보조 설명은 사용자 확인 대상(지시문 23 C).
Future<void> _loadPretendard() async {
  final loader = FontLoader('Pretendard');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    loader.addFont(
      File('assets/fonts/Pretendard-$weight.otf').readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
    );
  }
  await loader.load();
}

void main() {
  setUpAll(_loadPretendard);

  Future<void> openSheet(WidgetTester tester, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPaidCardInfoSheet(context),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  Finder sheet() => find.byKey(const ValueKey('paid-card-info-sheet'));
  Rect rel(WidgetTester tester, Finder finder) {
    final origin = tester.getTopLeft(sheet());
    final r = tester.getRect(finder);
    return Rect.fromLTWH(r.left - origin.dx, r.top - origin.dy, r.width, r.height);
  }

  testWidgets('시트 틀 `sp1xa` — 360 폭, 위 모서리 24, 채움 #FFFFFF, 화면 맨 아래에 붙는다', (tester) async {
    await openSheet(tester);

    expect(tester.getSize(sheet()).width, 360);
    final decoration = tester.widget<DecoratedBox>(sheet()).decoration as BoxDecoration;
    expect(decoration.color, const Color(0xFFFFFFFF));
    expect(decoration.borderRadius, const BorderRadius.vertical(top: Radius.circular(24)));
    expect(tester.getBottomLeft(sheet()).dy, 780);
  });

  testWidgets('손잡이 `EOSt5` 36×4 #DDDDDD, 맨 위에서 12 아래', (tester) async {
    await openSheet(tester);

    final handle = find.byKey(const ValueKey('paid-card-info-handle'));
    expect(rel(tester, handle), const Rect.fromLTWH(162, 12, 36, 4));
    final decoration = tester.widget<DecoratedBox>(find.descendant(of: handle, matching: find.byType(DecoratedBox)).first).decoration as BoxDecoration;
    expect(decoration.color, const Color(0xFFDDDDDD));
  });

  testWidgets('제목 `aaNm1` "이렇게 정밀하게 골랐어요" 20/700 #222222, 왼쪽 16 · 위 36(손잡이 칸 28 + 안쪽 8)', (tester) async {
    await openSheet(tester);

    final title = find.text('이렇게 정밀하게 골랐어요');
    final style = tester.widget<Text>(title).style!;
    expect(style.fontSize, 20);
    expect(style.fontWeight, FontWeight.w700);
    expect(style.color, const Color(0xFF222222));
    final box = rel(tester, title);
    expect(box.left, 16);
    expect(box.top, closeTo(28 + 8, 0.5));
    expect(box.height, closeTo(29, 0.5));
  });

  testWidgets('설명 `du9NW` 14/400/1.55 #6A6A6A — pen 문구 그대로', (tester) async {
    await openSheet(tester);

    final desc = find.text('내 프로필과 상대 프로필을 네 가지로 나눠 비교해 점수를 매겼어요.');
    final style = tester.widget<Text>(desc).style!;
    expect(style.fontSize, 14);
    expect(style.fontWeight, FontWeight.w400);
    expect(style.height, 1.55);
    expect(style.color, const Color(0xFF6A6A6A));
    expect(rel(tester, desc).left, 16);
  });

  testWidgets('네 줄 — 순서 · 아이콘 36×36 · 제목 15/700/1.4 · 설명 14/400/1.45 #6A6A6A, 글 상자는 아이콘 오른쪽 12', (tester) async {
    await openSheet(tester);

    const rows = [
      (AppIcon3d.chat, '성향 9가지 비교', '집콕·밖으로부터 익숙한 것·새로운 것까지 설문 답을 하나하나 비교해요'),
      (AppIcon3d.tags, '관심사와 특징 태그', '겹치는 관심사가 많을수록 점수가 올라가요'),
      (AppIcon3d.sparkles, 'AI 글 분석', "자기소개와 '이런 사람이 좋아요' 글의 의미를 AI가 서로 비교해요"),
      (AppIcon3d.badgeCheck, '원하는 조건 반영', '나이·키·MBTI·흡연·종교 조건이 맞을수록 높게 쳐요'),
    ];
    var previousTop = -1.0;
    for (final (icon, title, description) in rows) {
      final iconFinder = find.descendant(of: sheet(), matching: find.byWidgetPredicate((w) => w is Icon3d && w.icon == icon));
      expect(iconFinder, findsOneWidget, reason: title);
      final iconRect = rel(tester, iconFinder);
      expect(iconRect.size, const Size(36, 36), reason: title);
      expect(iconRect.left, 16, reason: title);
      expect(iconRect.top, greaterThan(previousTop), reason: title);
      previousTop = iconRect.top;

      final titleStyle = tester.widget<Text>(find.text(title)).style!;
      expect(titleStyle.fontSize, 15, reason: title);
      expect(titleStyle.fontWeight, FontWeight.w700, reason: title);
      expect(titleStyle.height, 1.4, reason: title);
      expect(titleStyle.color, const Color(0xFF222222), reason: title);
      expect(rel(tester, find.text(title)).left, 16 + 36 + 12, reason: title);
      expect(rel(tester, find.text(title)).top, closeTo(iconRect.top, 0.5), reason: title);

      final descStyle = tester.widget<Text>(find.text(description)).style!;
      expect(descStyle.fontSize, 14, reason: title);
      expect(descStyle.fontWeight, FontWeight.w400, reason: title);
      expect(descStyle.height, 1.45, reason: title);
      expect(descStyle.color, const Color(0xFF6A6A6A), reason: title);
      // 제목과 설명 사이 2.
      expect(rel(tester, find.text(description)).top - rel(tester, find.text(title)).bottom, closeTo(2, 0.5), reason: title);
    }
  });

  testWidgets('강조 상자 `vMtVN` — 폭 328, padding 14, 모서리 12, #FFF0F2, 14/700/1.5 #222222', (tester) async {
    await openSheet(tester);

    final box = find.byKey(const ValueKey('paid-card-info-highlight'));
    final rect = rel(tester, box);
    expect(rect.left, 16);
    expect(rect.width, 328);
    final decoration = tester.widget<DecoratedBox>(box).decoration as BoxDecoration;
    expect(decoration.color, AppColors.primaryWash);
    expect(decoration.color, const Color(0xFFFFF0F2));
    expect(decoration.borderRadius, BorderRadius.circular(12));
    final text = find.text('이 분석으로 나와 가장 잘 맞는 사람들 가운데 한 명을 골랐어요');
    final style = tester.widget<Text>(text).style!;
    expect(style.fontSize, 14);
    expect(style.fontWeight, FontWeight.w700);
    expect(style.height, 1.5);
    expect(style.color, const Color(0xFF222222));
    expect(rel(tester, text).left - rect.left, 14);
    expect(rel(tester, text).top - rect.top, 14);
    // pen 상자 72 = 위아래 14 + 글 44(속성 1.5 → 두 줄 42, pen 렌더 44).
    expect(rect.height, closeTo(72, 3));
  });

  testWidgets('확인 버튼 `yqPNS` — 폭 328 · 높이 52 · 모서리 14 · #FF385C, "알겠어요" 16/700 #FFFFFF + 오른쪽 화살표 20, 누르면 닫힌다', (tester) async {
    await openSheet(tester);

    final button = find.byKey(const ValueKey('paid-card-info-confirm'));
    final rect = rel(tester, button);
    expect(rect.left, 16);
    expect(rect.size, const Size(328, 52));
    final material = tester.widget<Material>(find.descendant(of: button, matching: find.byType(Material)).first);
    expect((material.shape! as RoundedRectangleBorder).borderRadius, BorderRadius.circular(14));
    final style = tester.widget<Text>(find.descendant(of: button, matching: find.text('알겠어요'))).style!;
    expect(style.fontSize, 16);
    expect(style.fontWeight, FontWeight.w700);
    final arrow = tester.widget<Icon>(find.descendant(of: button, matching: find.byType(Icon)));
    expect(arrow.icon, AppIcons.arrowRight);
    expect(arrow.size, 20);
    // 아이콘 색은 버튼 글자색(onPrimary)을 물려받는다.
    expect(IconTheme.of(tester.element(find.descendant(of: button, matching: find.byType(Icon)))).color, const Color(0xFFFFFFFF));

    await tester.tap(find.text('알겠어요'));
    await tester.pumpAndSettle();

    expect(sheet(), findsNothing);
  });

  testWidgets('위에서 아래로 쌓인 간격 — 설명 아래 16 · 줄 사이 16 · 줄 아래 16 · 강조 상자 아래 16 · 버튼 아래 32', (tester) async {
    await openSheet(tester);

    final desc = rel(tester, find.text('내 프로필과 상대 프로필을 네 가지로 나눠 비교해 점수를 매겼어요.'));
    final firstIcon = rel(tester, find.descendant(of: sheet(), matching: find.byWidgetPredicate((w) => w is Icon3d && w.icon == AppIcon3d.chat)));
    final lastIcon = rel(tester, find.descendant(of: sheet(), matching: find.byWidgetPredicate((w) => w is Icon3d && w.icon == AppIcon3d.badgeCheck)));
    final highlight = rel(tester, find.byKey(const ValueKey('paid-card-info-highlight')));
    final confirm = rel(tester, find.byKey(const ValueKey('paid-card-info-confirm')));
    expect(firstIcon.top - desc.bottom, closeTo(16, 0.5));
    expect(highlight.top - lastIcon.top, greaterThan(40));
    expect(confirm.top - highlight.bottom, 16);
    expect(tester.getSize(sheet()).height - confirm.bottom, 32);
  });

  testWidgets('점수 숫자 · 순위 · 비중 · 학교 이름이 시트 어디에도 없다 (30/20/50 · 상위 20%)', (tester) async {
    await openSheet(tester);

    final all = [for (final t in tester.widgetList<Text>(find.descendant(of: sheet(), matching: find.byType(Text)))) t.data ?? ''].join('|');
    for (final banned in ['%', '상위', '30', '대학교', '이상형 조건에 맞는']) {
      expect(all.contains(banned), isFalse, reason: banned);
    }
  });

  testWidgets('글자를 키워도(2.0) 시트가 스크롤되고 넘치지 않으며 확인 버튼에 닿을 수 있다', (tester) async {
    await openSheet(tester, textScale: 2);

    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('알겠어요'));
    await tester.tap(find.text('알겠어요'));
    await tester.pumpAndSettle();

    expect(sheet(), findsNothing);
  });
}
