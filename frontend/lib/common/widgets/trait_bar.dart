import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 표시 전용 성향 바(DESIGN.md §8.1 10b — 입력용 `TraitSlider` 와 별개다).
/// 라벨 고정폭 60 · 간격 8 · 바 150 은 시안 실측값이다(2026-09-13 라운드2 에서
/// 라벨 64 → 60 으로 줄여 우측 라벨이 잘리던 버그를 고쳤다 — 되돌리지 않는다).
///
/// 2026-09-23: 실기기 대조에서 pen `TORAs` 와 어긋나 트랙을 2 선 + 점 12 에서
/// **6 굵기 트랙 + 16×6 표시**로 바꿨다. 표시가 트랙 안에 머물러 양 끝에서 잘리지 않는다.
class TraitBar extends StatelessWidget {
  const TraitBar({
    required this.leftLabel,
    required this.rightLabel,
    required this.value,
    super.key,
  });

  final String leftLabel;
  final String rightLabel;

  /// -1.0 ~ 1.0
  final double value;

  @override
  Widget build(BuildContext context) {
    final ratio = ((value + 1) / 2).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            leftLabel,
            style: AppTypography.caption.copyWith(color: AppColors.muted),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        SizedBox(
          width: 150,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: AppColors.surfaceStrong,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Align(
                alignment: Alignment(ratio * 2 - 1, 0),
                child: Container(
                  width: 16,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        SizedBox(
          width: 60,
          child: Text(
            // 오른쪽 라벨도 왼쪽 정렬이다(pen `TORAs`) — 줄마다 글자 시작점이 맞는다.
            rightLabel,
            style: AppTypography.caption.copyWith(color: AppColors.muted),
          ),
        ),
      ],
    );
  }
}
