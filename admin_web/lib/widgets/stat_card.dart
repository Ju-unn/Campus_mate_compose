import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:flutter/material.dart';

/// pen Web/StatCard(FP6Ml): 폭 280 · 높이 146(A5 · A8 PNG 측정 — 글자를 키우면 이보다 커진다) · web-surface · web-outline 1 · 모서리 14 · 안쪽 24 ·
/// 라벨 14/600 web-muted → 12 → 값 32/700 web-ink → (있으면) 8 → [footer]. 값은 일반 Text 로만 그린다.
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, this.footer});

  static const double width = 280;
  static const double height = 146;

  final String label;
  final String value;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(AdminRadius.md);
    final footer = this.footer;
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: height),
      padding: const EdgeInsets.all(AdminSpacing.lg),
      decoration: BoxDecoration(color: AdminColors.surface, borderRadius: shape),
      foregroundDecoration: BoxDecoration(borderRadius: shape, border: Border.all(color: AdminColors.outline)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AdminTypography.smStrong.copyWith(height: AdminTypography.smBox, color: AdminColors.muted)),
          const SizedBox(height: AdminSpacing.sm),
          // 큰 글자에서 숫자가 줄을 바꾸지 않게 카드 안쪽 폭에 맞춰 줄인다
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: AdminTypography.stat.copyWith(color: AdminColors.ink)),
          ),
          if (footer != null) ...[const SizedBox(height: AdminSpacing.xs), footer],
        ],
      ),
    );
  }
}
