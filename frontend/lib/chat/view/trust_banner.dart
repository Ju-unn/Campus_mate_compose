import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 채팅방 헤더 아래 배너(pen `teNRJ` Notice). 세 가지가 같은 자리를 쓴다 —
/// 미리 수락(pen 없음) · 14g 대기(`A1g5lB`) · 14h 종료 예정(`bAZox`).
class TrustBanner extends StatelessWidget {
  const TrustBanner({
    required this.title,
    required this.caption,
    this.isMuted = false,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String caption;

  /// 종료 예정(14h)은 회색 바탕이다 — 좋은 소식이 아닌 자리에 분홍을 쓰지 않는다.
  final bool isMuted;

  /// 미리 수락 배너에만 버튼이 있다. 거절 버튼은 두지 않는다 —
  /// 24시간 전의 거절은 되돌릴 수 없는데 얻는 게 없다(시트에서 충분히 고민한 뒤에 하면 된다).
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: isMuted ? AppColors.surfaceSoft : AppColors.primaryWash,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isMuted ? AppIcons.timer : AppIcons.shieldCheck,
                size: 20,
                color: isMuted ? AppColors.muted : AppColors.primaryText,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.labelSmall.copyWith(color: AppColors.ink),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      caption,
                      style: AppTypography.caption.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: AppSpacing.sm),
            AppButton(label: actionLabel!, onPressed: onAction, height: 44),
          ],
        ],
      ),
    );
  }
}
