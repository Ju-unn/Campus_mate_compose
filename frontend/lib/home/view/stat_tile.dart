import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// stat-panel 한 칸(pen `krua8` 의 `zUQMn` · `Rp7wY` · `iwSBr`).
class StatTile extends StatelessWidget {
  const StatTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    this.iconScale = 1,
    super.key,
  });

  final AppIcon3d icon;
  final Color color;
  final String value;
  final String label;

  /// pen 이 36 칸 안에서 그림만 키운 배율(칸 크기는 그대로).
  final double iconScale;

  @override
  Widget build(BuildContext context) {
    // pen 높이 96 은 최소 높이다 — 글자를 키우면 늘어나고, 라벨은 줄을 바꾼다(DESIGN §11.2).
    return Container(
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.scale(scale: iconScale, child: Icon3d(icon, size: 36)),
          const SizedBox(height: 3),
          // 숫자가 길어져도 줄을 바꾸지 않고 칸 안에서 줄인다.
          FittedBox(
            fit: BoxFit.scaleDown,
            // softWrap 을 꺼야 줄 높이를 재는 IntrinsicHeight 가 두 줄로 세지 않는다.
            child: Text(value, softWrap: false, style: AppTypography.label.copyWith(color: AppColors.ink)),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
