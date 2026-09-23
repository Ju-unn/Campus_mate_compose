import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 카드 액션 바(DESIGN.md §8.2 · pen `TORAs`). 높이 56 · 사이 12 이고
/// **거절은 폭 104 고정**, 수락이 남은 폭을 전부 가진다 — 수락이 시각적으로 크되
/// 거절을 누르기 어렵게 만들지는 않는다.
///
/// 2026-09-23: 하단 고정 바에서 카드 아래 따라 흐르는 줄로 바뀌었다(pen). 그래서
/// 윗선·SafeArea·바깥 패딩이 없다 — 그건 화면이 정한다.
/// 모양이 §8.3 버튼 5종 어디에도 없어(거절 `surfaceStrong`·모서리 8) [AppButton] 을 쓰지 않는다.
class CardActionBar extends StatelessWidget {
  const CardActionBar({required this.onReject, required this.onAccept, super.key});

  final VoidCallback? onReject;
  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 104,
          child: _ActionButton(
            icon: AppIcons.x,
            label: '거절',
            background: AppColors.surfaceStrong,
            foreground: AppColors.ink,
            // 꺼졌을 때도 분홍(`primaryDisabled`)이 아니라 회색이다 — 거절은 분홍 계열이 아니다.
            disabledBackground: AppColors.surfaceStrong,
            radius: AppRadius.sm,
            iconGap: 6,
            onPressed: onReject,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _ActionButton(
            icon: AppIcons.heart,
            label: '수락하기',
            background: AppColors.primary,
            foreground: AppColors.onPrimary,
            disabledBackground: AppColors.primaryDisabled,
            radius: AppRadius.sm,
            iconGap: AppSpacing.xs,
            onPressed: onAccept,
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.disabledBackground,
    required this.radius,
    required this.iconGap,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final Color disabledBackground;
  final double radius;

  /// 아이콘과 글자 사이(pen `TORAs` — 거절 6, 수락 8).
  final double iconGap;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        disabledBackgroundColor: disabledBackground,
        disabledForegroundColor: AppColors.disabled,
        elevation: 0,
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 56),
        maximumSize: const Size(double.infinity, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          SizedBox(width: iconGap),
          Text(label, style: AppTypography.label),
        ],
      ),
    );
  }
}
