import 'package:cached_network_image/cached_network_image.dart';
import 'package:campus_mate/common/university_logos.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/common/widgets/school_label.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/matching/model/daily_card.dart';
import 'package:campus_mate/matching/view/daily_card_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _card = DailyCard(
  cardId: 'c1',
  source: CardSource.daily,
  profile: CardProfile(profileId: 't1', nickname: '여우비', age: 23, university: '테스트대학교', major: '컴퓨터공학과'),
);

Widget _scope(Widget child) => ProviderScope(
      overrides: [universityLogosProvider.overrideWith((ref) => const <String, String>{})],
      child: child,
    );

Future<void> _pump(WidgetTester tester, {DailyCard card = _card}) => tester.pumpWidget(
      _scope(MaterialApp(home: Scaffold(body: DailyCardSummary(card: card, onTap: () {})))),
    );

Future<void> _pumpNarrow(WidgetTester tester, DailyCard card, double scale) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _scope(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: const Size(360, 780), textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DailyCardSummary(card: card, onTap: () {}),
          ),
        ),
      ),
    )),
  );
}

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

  testWidgets('사진 `JvMzE` — 96 원으로 자르고 흰 링 3px 은 그 위에 덧그린다(링이 사진을 정사각으로 밀지 않는다)', (tester) async {
    const withAvatar = DailyCard(
      cardId: 'c1',
      source: CardSource.daily,
      profile: CardProfile(
        profileId: 't1',
        nickname: '여우비',
        age: 23,
        university: '테스트대학교',
        major: '컴퓨터공학과',
        avatarUrl: 'https://example.invalid/a.webp',
      ),
    );
    await _pump(tester, card: withAvatar);

    final photo = find.byType(CachedNetworkImage);
    final clip = find.ancestor(of: photo, matching: find.byType(ClipOval));
    expect(clip, findsOneWidget);
    // 원이 아니라 정사각으로 잘리던 원인: Container 의 border 가 사진을 90 정사각으로 안쪽에 밀어 넣고, 바깥 96 원으로만 잘랐다.
    expect(tester.getSize(clip), const Size(96, 96));
    expect(tester.getSize(photo), const Size(96, 96));
    expect(tester.getCenter(photo), tester.getCenter(clip));

    final box = find.ancestor(of: clip, matching: find.byType(Container)).first;
    final ring = tester.widget<Container>(box).foregroundDecoration! as BoxDecoration;
    expect(tester.getSize(box), const Size(96, 96));
    expect(ring.shape, BoxShape.circle);
    expect(ring.border, Border.all(color: AppColors.canvas, width: 3));
  });

  testWidgets('사진이 아직 없는 사람도 96 원 안에 회색 바탕과 아이콘이 앉는다', (tester) async {
    await _pump(tester);

    final clip = find.descendant(of: find.byType(DailyCardSummary), matching: find.byType(ClipOval));
    expect(clip, findsOneWidget);
    expect(tester.getSize(clip), const Size(96, 96));
    expect(find.descendant(of: clip, matching: find.byIcon(AppIcons.userRound)), findsOneWidget);
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

  group('구매 카드 배지 `ZvKiJ`(카드 `mj74J`, 마스터 Badge `XPRBv` 인스턴스)', () {
    final purchased = DailyCard(cardId: 'c2', source: CardSource.purchased, profile: _card.profile);

    testWidgets('구매 카드에는 "구매 카드" 알약이 있다 — #E00B41 채움 · 모서리 999 · 30 높이 · 패딩 10', (tester) async {
      await _pump(tester, card: purchased);

      final label = find.text('구매 카드');
      expect(label, findsOneWidget);
      final style = tester.widget<Text>(label).style!;
      expect(style.fontSize, 11);
      expect(style.fontWeight, FontWeight.w600);
      expect(style.color, const Color(0xFFFFFFFF));
      final pill = find.ancestor(of: label, matching: find.byType(Container)).first;
      final decoration = tester.widget<Container>(pill).decoration! as BoxDecoration;
      expect(decoration.color, const Color(0xFFE00B41));
      expect(decoration.borderRadius, BorderRadius.circular(AppRadius.pill)); // pen 999 = 알약. 앱 토큰 pill 은 9999 라 모양이 같다
      expect(tester.getSize(pill).height, 30);
      // 아이콘 왼쪽 패딩 10, 아이콘과 글자 사이 4.
      final icon = find.descendant(of: pill, matching: find.byIcon(AppIcons.shoppingBag));
      expect(icon, findsOneWidget);
      expect(tester.widget<Icon>(icon).size, 18);
      expect(tester.widget<Icon>(icon).color, const Color(0xFFFFFFFF));
      expect(tester.getTopLeft(icon).dx - tester.getTopLeft(pill).dx, 10);
      expect(tester.getTopLeft(label).dx - tester.getTopRight(icon).dx, 4);
    });

    testWidgets('구매 카드는 만료가 없어 시계 배지가 없고, 학생 인증은 그대로 오른쪽 끝(구매 카드와 사이 6)', (tester) async {
      await _pump(tester, card: purchased);

      expect(find.textContaining('까지'), findsNothing);
      expect(tester.widgetList<Icon3d>(find.byType(Icon3d)).map((i) => i.icon), [AppIcon3d.badgeCheck]);
      final paidPill = find.ancestor(of: find.text('구매 카드'), matching: find.byType(Container)).first;
      final studentPill = find.ancestor(of: find.text('학생 인증'), matching: find.byType(Container)).first;
      expect(tester.getTopLeft(studentPill).dx - tester.getTopRight(paidPill).dx, 6);
      final frame = tester.getRect(find.byType(DailyCardSummary));
      expect(frame.right - tester.getTopRight(studentPill).dx, 21); // 안쪽 20 + 테두리 1
    });

    testWidgets('무료 카드에는 구매 카드 배지가 없다', (tester) async {
      await _pump(tester);

      expect(find.text('구매 카드'), findsNothing);
      expect(find.byIcon(AppIcons.shoppingBag), findsNothing);
    });

    for (final scale in [1.3, 2.0]) {
      testWidgets('360 폭 · 글자 배율 $scale 에서 구매 카드 배지가 카드 밖으로 넘치지 않는다', (tester) async {
        await _pumpNarrow(tester, purchased, scale);

        expect(tester.takeException(), isNull);
        final inner = tester.getRect(find.byType(DailyCardSummary));
        final pill = tester.getRect(find.ancestor(of: find.text('구매 카드'), matching: find.byType(Container)).first);
        expect(pill.right, lessThanOrEqualTo(inner.right - 21));
        expect(pill.left, greaterThanOrEqualTo(inner.left + 21));
      });
    }

    testWidgets('글자 배율 2.0 에서 세 배지가 한 줄에 안 들어가면 다음 줄로 내려가고 넘치지 않는다', (tester) async {
      // 구매 카드에 만료가 함께 오는 경우는 없지만, 줄바꿈이 세 알약 모두에 먹는지 보려고 일부러 겹친다.
      final both = DailyCard(
        cardId: 'c2',
        source: CardSource.purchased,
        profile: _card.profile,
        expiresAt: DateTime(2026, 10, 8, 7),
      );
      await _pumpNarrow(tester, both, 2.0);

      expect(tester.takeException(), isNull);
      final tops = {
        for (final text in ['목요일 오전 7시까지', '구매 카드', '학생 인증'])
          text: tester.getTopLeft(find.ancestor(of: find.text(text), matching: find.byType(Container)).first).dy,
      };
      expect(tops.values.toSet().length, greaterThan(1), reason: '한 줄에 다 들어가면 줄바꿈 시험이 못 된다: $tops');
      final frame = tester.getRect(find.byType(DailyCardSummary));
      for (final text in tops.keys) {
        final pill = tester.getRect(find.ancestor(of: find.text(text), matching: find.byType(Container)).first);
        expect(pill.right, lessThanOrEqualTo(frame.right - 21));
      }
    });
  });

  testWidgets('링크 줄 — 화살표 `t4484l` 은 오른쪽 끝, 줄 사이 16', (tester) async {
    await _pump(tester);

    final frame = tester.getRect(find.byType(DailyCardSummary));
    final chevron = find.byIcon(AppIcons.chevronRight);
    expect(frame.right - tester.getTopRight(chevron).dx, 21); // 안쪽 20 + 테두리 1
    final avatar = find.ancestor(of: find.byIcon(AppIcons.userRound), matching: find.byType(Container)).first;
    expect(tester.getTopLeft(find.byType(Divider)).dy - tester.getBottomLeft(avatar).dy, 16);
  });

  testWidgets('학교 줄 `dmdKV` = SchoolLabel(학교로 로고를 찾고 "학교 · 학과" 를 그린다)', (tester) async {
    await _pump(tester);

    final label = tester.widget<SchoolLabel>(find.byType(SchoolLabel));
    expect(label.university, '테스트대학교');
    expect(label.text, '테스트대학교 · 컴퓨터공학과');
    expect(label.style.fontSize, 14);
    expect(label.style.color, const Color(0xFF6A6A6A));
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('360 폭 · 글자 배율 $scale 에서 배지 줄이 넘치지 않는다', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final card = DailyCard(cardId: 'c1', source: CardSource.daily, profile: _card.profile, expiresAt: DateTime(2026, 10, 8, 7));
      await tester.pumpWidget(
        _scope(MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: const Size(360, 780), textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DailyCardSummary(card: card, onTap: () {}),
              ),
            ),
          ),
        )),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('목요일 오전 7시까지'), findsOneWidget);
    });
  }
}
