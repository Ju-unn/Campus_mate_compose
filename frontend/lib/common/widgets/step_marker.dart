import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 진행 단계 표시(datingApp.pen `StepMarker · Done` · `· Active` · `· Wait`).
enum StepMarkerStatus { done, active, wait }

/// 06-2b 초안 만들기처럼 "지금 무엇을 하고 있는지" 를 줄줄이 보여주는 자리에 쓴다.
class StepMarker extends StatelessWidget {
  const StepMarker({required this.label, required this.status, super.key});

  final String label;
  final StepMarkerStatus status;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(_icon, size: 18, color: _iconColor),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: _labelStyle),
      ],
    );
  }

  IconData get _icon {
    return switch (status) {
      StepMarkerStatus.done => AppIcons.circleCheck,
      StepMarkerStatus.active => AppIcons.circleDot,
      StepMarkerStatus.wait => AppIcons.circle,
    };
  }

  Color get _iconColor {
    return switch (status) {
      StepMarkerStatus.done => AppColors.success,
      StepMarkerStatus.active => AppColors.primaryText,
      StepMarkerStatus.wait => AppColors.hairline,
    };
  }

  TextStyle get _labelStyle {
    return switch (status) {
      StepMarkerStatus.done => AppTypography.bodySmall.copyWith(color: AppColors.body),
      StepMarkerStatus.active => AppTypography.labelSmall.copyWith(color: AppColors.ink),
      StepMarkerStatus.wait => AppTypography.bodySmall.copyWith(color: AppColors.disabled),
    };
  }
}
