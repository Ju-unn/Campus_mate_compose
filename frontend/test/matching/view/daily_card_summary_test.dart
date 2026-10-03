import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/matching/model/daily_card.dart';
import 'package:campus_mate/matching/view/daily_card_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _card = DailyCard(
  cardId: 'c1',
  source: CardSource.daily,
  profile: CardProfile(profileId: 't1', nickname: '여우비', age: 23, university: '테스트대학교', major: '컴퓨터공학과'),
);

Future<void> _pump(WidgetTester tester, {DailyCard card = _card}) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DailyCardSummary(card: card, onTap: () {}))),
    );

BoxDecoration _frame(WidgetTester tester) => tester
    .widgetList<Container>(find.descendant(of: find.byType(DailyCardSummary), matching: find.byType(Container)))
    .map((c) => c.decoration)
    .whereType<BoxDecoration>()
    .first;

void main() {
  testWidgets('카드 틀 `v26S7z` 그림자 = AppElevation.cardSoft(2026-10-01 완화)', (tester) async {
    await _pump(tester);

    expect(_frame(tester).boxShadow, AppElevation.cardSoft);
  });

  testWidgets('링크 `t4484l` "프로필 자세히 보기" = 14/600 #C4224B', (tester) async {
    await _pump(tester);

    final style = tester.widget<Text>(find.text('프로필 자세히 보기')).style!;
    expect(style.fontSize, 14);
    expect(style.fontWeight, FontWeight.w600);
    expect(style.color, const Color(0xFFC4224B));
  });

  testWidgets('배지 줄 `kaRGO` — 시계 `ZMHUK` "목요일 오전 7시까지" · 학생 인증 `aRL8x` 3D 18, 오른쪽 정렬 사이 6', (tester) async {
    // 2026-10-08 은 목요일. 만료 시각이 곧 다음 지급 시각이다.
    final card = DailyCard(
      cardId: _card.cardId,
      source: CardSource.daily,
      profile: _card.profile,
      expiresAt: DateTime(2026, 10, 8, 7),
    );
    await _pump(tester, card: card);

    final clock = find.text('목요일 오전 7시까지');
    expect(clock, findsOneWidget);
    expect(tester.widget<Text>(clock).style!.fontSize, 11);
    final icons = tester.widgetList<Icon3d>(find.byType(Icon3d)).map((i) => (i.icon, i.size));
    expect(icons, [(AppIcon3d.clock, 18.0), (AppIcon3d.badgeCheck, 18.0)]);
    final clockPill = find.ancestor(of: clock, matching: find.byType(Container)).first;
    final badgePill = find.ancestor(of: find.text('학생 인증'), matching: find.byType(Container)).first;
    expect(tester.getTopLeft(badgePill).dx - tester.getTopRight(clockPill).dx, 6);
    expect(tester.getSize(badgePill).height, 30);
  });

  testWidgets('만료 시각이 없는 카드(구매 카드)는 시계 배지가 없다', (tester) async {
    await _pump(tester);

    expect(find.textContaining('까지'), findsNothing);
    expect(find.byType(Icon3d), findsOneWidget);
  });

  testWidgets('링크 줄 — 화살표 `t4484l` 은 오른쪽 끝, 줄 사이 16', (tester) async {
    await _pump(tester);

    final frame = tester.getRect(find.byType(DailyCardSummary));
    final chevron = find.byIcon(AppIcons.chevronRight);
    expect(frame.right - tester.getTopRight(chevron).dx, 21); // 안쪽 20 + 테두리 1
    final avatar = find.ancestor(of: find.byIcon(AppIcons.userRound), matching: find.byType(Container)).first;
    expect(tester.getTopLeft(find.byType(Divider)).dy - tester.getBottomLeft(avatar).dy, 16);
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('360 폭 · 글자 배율 $scale 에서 배지 줄이 넘치지 않는다', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final card = DailyCard(cardId: 'c1', source: CardSource.daily, profile: _card.profile, expiresAt: DateTime(2026, 10, 8, 7));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: const Size(360, 780), textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DailyCardSummary(card: card, onTap: () {}),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('목요일 오전 7시까지'), findsOneWidget);
    });
  }
}
