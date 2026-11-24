import 'package:campus_mate/community/view/community_card_parts.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 투표 카드(`ffFIS`) · 게시물 카드(`WHqdP` · `UCWuL`)가 같이 쓰는 조각.
void main() {
  Future<void> pumpIn(WidgetTester tester, Widget child) => tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: Center(child: SizedBox(width: 328, child: child))),
        ),
      );

  testWidgets('CommunityCardFrame: 흰 · 모서리 24 · 그림자 homeTileLow, 누르면 알리고 눌림 효과는 틀 안 Material 에 갇힌다', (tester) async {
    var taps = 0;
    await pumpIn(
      tester,
      CommunityCardFrame(padding: const EdgeInsets.all(16), onTap: () => taps++, child: const SizedBox(height: 40)),
    );
    final decoration = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first).decoration as ShapeDecoration;
    expect((decoration.color, decoration.shadows), (AppColors.canvas, AppElevation.homeTileLow));
    expect(tester.getSize(find.byType(CommunityCardFrame)), const Size(328, 72));
    await tester.tap(find.byType(CommunityCardFrame));
    expect(taps, 1);
    final material = find.ancestor(of: find.byType(InkWell), matching: find.byType(Material)).first;
    expect(tester.getSize(material), const Size(328, 72));
  });

  testWidgets('CommunityCardHeader: 오른쪽 버튼이 없어도 높이 48, 아바타 40 → 10 → "익명"', (tester) async {
    await pumpIn(tester, CommunityCardHeader(createdAt: DateTime(2026, 11, 24, 14), now: DateTime(2026, 11, 24, 14), avatarKey: const Key('a')));
    expect(tester.getSize(find.byType(CommunityCardHeader)).height, 48);
    final avatar = tester.getRect(find.byKey(const Key('a')));
    expect(avatar.size, const Size(40, 40));
    expect(tester.getRect(find.text('익명')).left - avatar.right, 10);
  });

  testWidgets('CommunityMoreButton: 누름 48 · ellipsis 20 muted · 낭독 "더보기"', (tester) async {
    var taps = 0;
    await pumpIn(tester, Align(child: CommunityMoreButton(onPressed: () => taps++)));
    expect(tester.getSize(find.byType(IconButton)), const Size(48, 48));
    final icon = tester.widget<Icon>(find.byIcon(AppIcons.ellipsis));
    expect((icon.size, icon.color), (20, AppColors.muted));
    await tester.tap(find.byTooltip('더보기'));
    expect(taps, 1);
  });

  testWidgets('CommunityCardSeparator: 폭 꽉 · 1 · hairline-soft', (tester) async {
    await pumpIn(tester, const CommunityCardSeparator());
    expect(tester.getSize(find.byType(CommunityCardSeparator)), const Size(328, 1));
    expect(tester.widget<ColoredBox>(find.byType(ColoredBox).last).color, AppColors.hairlineSoft);
  });
}
