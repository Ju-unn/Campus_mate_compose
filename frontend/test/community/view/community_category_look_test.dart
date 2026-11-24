import 'package:campus_mate/community/model/data/community_category.dart';
import 'package:campus_mate/community/view/community_category_look.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 카테고리 → 글자 · 3D 그림은 이 한 곳이 정한다(칩 · 라벨 · 탭이 같이 쓴다).
void main() {
  testWidgets('자유 · 진로 · 연애 글자와 탭 그림(새 카테고리 3D 그림 셋)', (tester) async {
    late AppLocalizations l10n;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (context) {
          l10n = AppLocalizations.of(context);
          return const SizedBox();
        }),
      ),
    );
    expect(
      {for (final category in CommunityCategory.values) category: (category.label(l10n), category.icon)},
      {
        CommunityCategory.free: ('자유', AppIcon3d.categoryFree),
        CommunityCategory.career: ('진로', AppIcon3d.categoryCareer),
        CommunityCategory.love: ('연애', AppIcon3d.categoryLove),
      },
    );
  });
}
