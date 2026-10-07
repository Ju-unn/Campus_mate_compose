import 'package:campus_mate/billing/model/heart_bundles.dart';
import 'package:campus_mate/billing/view/heart_purchase_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 하단 구매바(pen `GG0ei` HeartPurchaseBar 360×88). 고른 번들 이름(추천이면 위에 "추천")과 구매 버튼.
/// 흰 바탕 · 위쪽 선 1px #EBEBEB · 안쪽 [12,16,24,16] · 간격 12. 기기 아래 여백은 그 밑에 더한다.
class HeartPurchaseBar extends StatelessWidget {
  const HeartPurchaseBar({required this.bundle, required this.onPurchase, super.key});

  final HeartBundle bundle;
  final VoidCallback onPurchase;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.canvas,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.hairlineSoft)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (bundle.isRecommended)
                        Text('추천', style: AppTypography.caption.copyWith(color: AppColors.primaryText)),
                      Text(
                        bundle.quantityLabel,
                        style: AppTypography.bodyStrong.copyWith(color: AppColors.ink, height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                HeartPurchaseButton(onPressed: onPurchase),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
