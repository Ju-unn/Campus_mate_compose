import 'package:campus_mate/community/model/data/community_category.dart';
import 'package:campus_mate/community/view/community_category_look.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 카드 안 "글 분류" 표시(pen CategoryLabel · Small `Xbtho`, 누르는 것 아님): primary-wash 알약 · 안쪽 [4,10] ·
/// 14/700 lh1.3 primary-text. 렌더 46×26("연애"). 글자 폭만 차지하고 왼쪽에 붙는다.
class CategoryLabel extends StatelessWidget {
  const CategoryLabel({required this.category, super.key});

  final CommunityCategory category;

  /// pen padding 좌우 10 — 간격 토큰 xs(8) · sm(12) 사이 값.
  static const double _sidePadding = 10;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      heightFactor: 1,
      child: DecoratedBox(
        decoration: const ShapeDecoration(color: AppColors.primaryWash, shape: StadiumBorder()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _sidePadding, vertical: AppSpacing.xxs),
          child: Text(
            category.label(context.l10n),
            style: AppTypography.labelSmall.copyWith(fontWeight: FontWeight.w700, height: 1.3, color: AppColors.primaryText),
          ),
        ),
      ),
    );
  }
}
