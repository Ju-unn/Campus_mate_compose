import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 선택 개수 막대(datingApp.pen `CJQLe` — 04-5 `yTzKR` · 04-6 `TwEKF` · 06-2 `lGtYh`).
///
/// 한 줄 가운데로 **막대 → 문구 → 최소 안내** 를 모은다(간격 8, 패딩·배경·테두리 없음).
/// 폭이 모자라면 한 줄을 고집하지 않고 다음 줄로 흘린다.
/// - 막대 `wuVCu` 안 `rPoWT` 외 4개: 20×4 알약, 간격 4, 찬 것 primary · 빈 것 hairline
/// - 문구 `GzSZ3`: 14/600, 줄 높이 20. 색은 **문구 전체에 한 색**이다 — 숫자만 따로 칠하지 않는다
/// - 최소 안내 `R89CUA`: 14/400, 줄 높이 20, 최소 개수를 못 채운 동안만 보인다(자리와 간격이 같이 사라진다)
///
/// 두 글자의 줄 높이를 20 으로 못박는다 — 글꼴 기본값(21.7/16.8)에 맡기면 안내가 사라질 때
/// 줄 높이가 바뀌어 하단 막대 전체가 위아래로 들썩인다.
class SelectCountBar extends StatelessWidget {
  const SelectCountBar({
    required this.selected,
    required this.max,
    required this.min,
    super.key,
  });

  final int selected;

  /// 고를 수 있는 최대 개수 = 막대 개수.
  final int max;

  /// 이만큼 못 채우면 안내를 붙이고 문구를 흐리게 둔다.
  final int min;

  @override
  Widget build(BuildContext context) {
    // 좁은 기기·큰 글씨에서 한 줄이 안 들어가면 **줄을 늘려 흘린다**. 통째로 줄이면(FittedBox)
    // 글씨 확대(DESIGN.md §11.2)로 키운 글자를 도로 줄여 버리고, 넘치게 두면 안내가 잘린다.
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.xs,
      // pen 에는 두 줄이 되는 경우가 없다 — 줄 사이는 칩 간격과 같은 4 로 둔다.
      runSpacing: AppSpacing.xxs,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < max; index++) ...[
              if (index > 0) const SizedBox(width: AppSpacing.xxs),
              Container(
                width: 20,
                height: 4,
                decoration: BoxDecoration(
                  color: index < selected ? AppColors.primary : AppColors.hairline,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ],
          ],
        ),
        Text(
          '$selected/$max개 선택',
          style: AppTypography.labelSmall.copyWith(color: _color, height: _lineHeight / 14),
        ),
        if (selected < min)
          Text(
            '· 최소 $min개',
            style: AppTypography.bodySmall.copyWith(color: AppColors.error, height: _lineHeight / 14),
          ),
      ],
    );
  }

  /// pen 이 그린 줄 높이(두 글자 모두 렌더 20).
  static const double _lineHeight = 20;

  Color get _color {
    if (selected < min) {
      return AppColors.muted;
    }
    return selected == max ? AppColors.primaryText : AppColors.ink;
  }
}
