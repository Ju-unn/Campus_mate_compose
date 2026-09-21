import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// 카드 액션 바(DESIGN.md §8.2). 거절 40% · 수락 60%, 높이 56, 사이 간격 `{space.sm}`.
/// 수락이 시각적으로 더 크다 — 거절을 어렵게 만들지는 않는다.
class CardActionBar extends StatelessWidget {
  const CardActionBar({required this.onReject, required this.onAccept, super.key});

  final VoidCallback? onReject;
  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.canvas,
          border: Border(top: BorderSide(color: AppColors.hairline)),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              flex: 40,
              child: AppButton(
                label: '거절',
                onPressed: onReject,
                variant: AppButtonVariant.secondary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(flex: 60, child: AppButton(label: '수락', onPressed: onAccept)),
          ],
        ),
      ),
    );
  }
}
