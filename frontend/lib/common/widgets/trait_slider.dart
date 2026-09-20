import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 성향 설문 슬라이더(datingApp.pen `TraitSlider`).
/// 5단계를 점으로 고르고 숫자는 보여주지 않는다(DESIGN.md §6.2 -1/-0.5/0/0.5/1).
class TraitSlider extends StatelessWidget {
  const TraitSlider({
    required this.value,
    required this.onChanged,
    required this.leftLabel,
    required this.rightLabel,
    super.key,
  });

  static const List<double> steps = [-1, -0.5, 0, 0.5, 1];

  /// 아직 고르지 않았으면 null — 어떤 점도 강조하지 않는다.
  final double? value;
  final ValueChanged<double> onChanged;
  final String leftLabel;
  final String rightLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 눈에 보이는 트랙은 22 높이지만, 손가락이 닿는 칸은 44 로 잡는다(DESIGN.md §5.3 최소 44×44).
        SizedBox(
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(height: 2, color: AppColors.hairline),
              Row(
                children: [
                  for (final step in steps)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(step),
                        child: Center(child: _dot(isSelected: value == step)),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(leftLabel, style: AppTypography.caption.copyWith(color: AppColors.muted)),
            Text(rightLabel, style: AppTypography.caption.copyWith(color: AppColors.muted)),
          ],
        ),
      ],
    );
  }

  Widget _dot({required bool isSelected}) {
    final size = isSelected ? 18.0 : 12.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary : AppColors.hairline,
        shape: BoxShape.circle,
      ),
    );
  }
}
