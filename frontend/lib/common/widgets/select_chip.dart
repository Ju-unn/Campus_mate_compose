import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 고르는 칩(datingApp.pen `Chip` 인스턴스 — 높이 35 · 알약 모서리).
/// 04-1 성별·내 MBTI, 06-1 선호 MBTI 처럼 짧은 낱말을 고르는 자리에 쓴다.
class SelectChip extends StatelessWidget {
  const SelectChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.width,
    this.height = 35,
    this.radius = AppRadius.sm,
    super.key,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  /// 디자인 파일이 칸 너비를 정해 둔 자리(성별 76, MBTI 48)에만 넘긴다.
  final double? width;

  /// 디자인 파일의 칸 높이. 04-1 `Chip` 은 35, 04-4·06-1 인상 칩(`BGMWX`)은 40 이다.
  final double height;

  /// 태그 칩은 모서리 8, 성별·MBTI 칩은 알약 모서리다.
  final double radius;

  @override
  Widget build(BuildContext context) {
    // 낭독기에 "고름/안 고름"이 들어가야 한다 — 색만으로는 전달되지 않는다.
    return Semantics(
      selected: isSelected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Ink(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryWash : AppColors.surfaceSoft,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: isSelected ? AppColors.primary : Colors.transparent),
          ),
          child: Center(
            child: Text(label, style: AppTypography.labelSmall.copyWith(color: AppColors.ink)),
          ),
        ),
      ),
    );
  }
}
