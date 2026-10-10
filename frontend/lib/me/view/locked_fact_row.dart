import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 15-6 "바꿀 수 없는 정보" 한 줄(pen 컴포넌트 `72. ProfileFactRow · Locked` `lhrPu`) — 296×48, 가로 gap 10, 세로 가운데.
/// 라벨 14/normal muted(`dBHS8`) · 오른쪽 값 14/600 disabled(`P3IFCy`) · 자물쇠 lucide lock 16 disabled(`faOKL`).
/// 누를 수 없는 읽기 전용 줄이다. 글자를 키우면 줄이 48 보다 커진다(DESIGN §11.2).
class LockedFactRow extends StatelessWidget {
  const LockedFactRow({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          Text(label, style: AppTypography.bodySmall.copyWith(color: AppColors.muted)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppTypography.bodySmall.copyWith(color: AppColors.disabled, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          const Icon(AppIcons.lock, size: 16, color: AppColors.disabled),
        ],
      ),
    );
  }
}
