import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 하트 스토어(18)와 구매 확인 시트(18d)가 같이 보이는 사용 제한 안내(pen `e1XTb` · `lKjQ7`).
/// 바탕 #F7F7F7 · 모서리 8 · 안쪽 16 · 글자 16/normal #3F3F3F 줄높이 1.6.
class HeartStoreNotice extends StatelessWidget {
  const HeartStoreNotice({super.key});

  static const String text = '추가 카드는 다음 카드가 올 때까지 한 장만 열 수 있어요. 산 카드는 결정할 때까지 사라지지 않아요.';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: AppColors.surfaceSoft, borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: Text(text, style: AppTypography.body.copyWith(color: AppColors.body)),
    );
  }
}
