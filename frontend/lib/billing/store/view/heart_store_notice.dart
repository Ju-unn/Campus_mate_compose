import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 하트 스토어(18)와 구매 확인 시트(18d)가 같이 보이는 사용 제한 안내(pen `e1XTb` · `lKjQ7`).
/// 바탕 #F7F7F7 · 모서리 8 · 안쪽 16 · 글자 16/normal #3F3F3F 줄높이 1.6.
class HeartStoreNotice extends StatelessWidget {
  const HeartStoreNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: AppColors.surfaceSoft, borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: Text(context.l10n.billingStoreNotice, style: AppTypography.body.copyWith(color: AppColors.body)),
    );
  }
}
