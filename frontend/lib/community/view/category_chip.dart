import 'package:campus_mate/community/model/data/community_category.dart';
import 'package:campus_mate/community/view/community_category_look.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 카테고리 고르기 칩(pen CategoryChip · Off `eYps8` / On `J8hpZ`). 보이는 높이 32, **누르는 영역만 44**(대장 판정 8 —
/// 보이는 모양은 그대로, 위아래 6 씩 투명하게 늘린다). 알약 · 안쪽 [0,14] · 글자 14 lh1.2.
/// Off = canvas 채움 + hairline 1 + body 600, On = primary-wash 채움 + primary 1.5 + primary-text 700. 테두리는 안쪽.
class CategoryChip extends StatelessWidget {
  const CategoryChip({required this.category, required this.selected, required this.onTap, super.key});

  final CommunityCategory category;
  final bool selected;
  final VoidCallback onTap;

  /// 보이는 알약. 시험이 높이 · 색을 잰다.
  static const surfaceKey = Key('category-chip-surface');

  static const double _height = 32;
  static const double _hitHeight = 44;

  /// pen padding [0,14] — 간격 토큰 sm(12) · md(16) 사이 값.
  static const double _sidePadding = 14;

  @override
  Widget build(BuildContext context) {
    final label = category.label(context.l10n);
    final side = selected
        ? const BorderSide(color: AppColors.primary, width: 1.5, strokeAlign: BorderSide.strokeAlignInside)
        : const BorderSide(color: AppColors.hairline, strokeAlign: BorderSide.strokeAlignInside);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        // 고른 모양이 바로 바뀌는 것이 눌림 알림이다 — 물결은 44 칸에 번져 보이는 알약 밖으로 나가 쓰지 않는다.
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _hitHeight),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: DecoratedBox(
              key: surfaceKey,
              decoration: ShapeDecoration(
                color: selected ? AppColors.primaryWash : AppColors.canvas,
                shape: StadiumBorder(side: side),
              ),
              child: ConstrainedBox(
                // 글자를 키우면 알약이 따라 커진다(32 는 최소).
                constraints: const BoxConstraints(minHeight: _height),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _sidePadding),
                  child: Center(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: Text(
                      label,
                      style: AppTypography.labelSmall.copyWith(
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                        color: selected ? AppColors.primaryText : AppColors.body,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
