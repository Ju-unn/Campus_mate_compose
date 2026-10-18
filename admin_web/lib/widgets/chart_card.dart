import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:flutter/material.dart';

/// pen Chart Card(egevB · A8 feZAY): web-surface · web-outline 1 · 모서리 14 · 안쪽 20 — 제목 16/700 + 알약(높이 24 · 12/600 web-muted ·
/// web-surface-strong, 오른쪽 끝) 줄 → 12 → 그래프. 그래프가 240 이면 카드 높이는 316.
class ChartCard extends StatelessWidget {
  const ChartCard({super.key, required this.title, required this.pill, required this.child, this.pillKey});

  final String title;
  final String pill;
  final Widget child;

  /// 알약 상자의 키(시험이 크기 · 바탕을 잰다)
  final Key? pillKey;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(AdminRadius.md);
    return Container(
      padding: const EdgeInsets.all(20), // pen egevB 안쪽 20 — 간격 표에 없는 값
      decoration: BoxDecoration(color: AdminColors.surface, borderRadius: shape),
      foregroundDecoration: BoxDecoration(borderRadius: shape, border: Border.all(color: AdminColors.outline)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title, style: AdminTypography.md.copyWith(fontWeight: FontWeight.w700, height: AdminTypography.mdBox, color: AdminColors.ink)),
                ),
              ),
              Container(
                key: pillKey,
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AdminColors.surfaceStrong, borderRadius: BorderRadius.circular(AdminRadius.pill)),
                child: Text(pill, style: AdminTypography.xsStrong.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted)),
              ),
            ],
          ),
          const SizedBox(height: AdminSpacing.sm),
          child,
        ],
      ),
    );
  }
}
