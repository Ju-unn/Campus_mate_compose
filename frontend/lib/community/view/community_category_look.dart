import 'package:campus_mate/community/model/data/community_category.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/l10n/app_localizations.dart';

/// 카테고리 → 화면 글자 · 탭 3D 그림. **이 한 곳**에서만 정한다 — 칩([CategoryChip]) · 라벨([CategoryLabel]) ·
/// 피드 탭 줄이 같이 쓴다. 색은 카테고리마다 다르지 않다(pen 칩 · 라벨이 셋 다 같은 색).
extension CommunityCategoryLook on CommunityCategory {
  /// pen 값표 19-1 탭 글자 · 칩 `eYps8` 글자 · 라벨 `Xbtho` 글자.
  String label(AppLocalizations l10n) => switch (this) {
        CommunityCategory.free => l10n.communityCategoryFree,
        CommunityCategory.career => l10n.communityCategoryCareer,
        CommunityCategory.love => l10n.communityCategoryLove,
      };

  /// 탭 그림(pen `GdxXY` · `UY6hz` · `k1bhXS` 자리). 대장이 준 카테고리 3D 그림 셋 — 탭 줄에서 28 로 그린다.
  AppIcon3d get icon => switch (this) {
        CommunityCategory.free => AppIcon3d.categoryFree,
        CommunityCategory.career => AppIcon3d.categoryCareer,
        CommunityCategory.love => AppIcon3d.categoryLove,
      };
}
