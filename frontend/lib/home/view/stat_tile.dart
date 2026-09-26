import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// stat-panel 한 칸(pen `zUQMn` · `Rp7wY` · `iwSBr`). Z54et 에 마스터가 없다.
class StatTile extends StatelessWidget {
  const StatTile({required this.icon, required this.value, required this.label, super.key});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    // pen 높이 76 은 최소 높이다 — 글자를 키우면 늘어나고, 라벨은 줄을 바꾼다(DESIGN §11.2).
    return Container(
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
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
