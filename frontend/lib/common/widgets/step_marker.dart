import 'package:campus_mate/common/widgets/app_lottie_view.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_lottie.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 진행 단계 표시(datingApp.pen `StepMarker · Done` · `· Active` · `· Wait`).
enum StepMarkerStatus { done, active, wait }

/// 06-2b 초안 만들기처럼 "지금 무엇을 하고 있는지" 를 줄줄이 보여주는 자리에 쓴다.
/// 진행 중([StepMarkerStatus.active])만 아이콘 대신 브랜드 스피너([AppLottie.brandSpinner])가 돈다 —
/// 스피너 파일을 못 읽으면 옛 점 아이콘으로 대신한다.
class StepMarker extends StatelessWidget {
  const StepMarker({required this.label, required this.status, super.key});

  final String label;
  final StepMarkerStatus status;

  /// 단계 아이콘 크기.
  static const double _iconSize = 18;

  /// 진행 중 스피너 크기(pen 06-2b `OPQvA` 22×22) — 아이콘 칸(18)보다 커서 칸 가운데에 겹쳐 넘치게 그린다.
  static const double _spinnerSize = 22;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 세 줄 모두 아이콘 칸은 18×18 이라 라벨이 같은 세로줄에 선다(pen `DAV2j`).
        SizedBox.square(
          dimension: _iconSize,
          child: status == StepMarkerStatus.active ? _spinner() : _statusIcon(),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: _labelStyle),
      ],
    );
  }

  Widget _statusIcon() => Icon(_icon, size: _iconSize, color: _iconColor);

  /// 칸 가운데에서 위아래 · 좌우로 2씩 넘친다(자르지 않는다).
  Widget _spinner() {
    return const OverflowBox(
      minWidth: _spinnerSize,
      maxWidth: _spinnerSize,
      minHeight: _spinnerSize,
      maxHeight: _spinnerSize,
      child: AppLottieView(scene: AppLottie.brandSpinner, width: _spinnerSize, height: _spinnerSize, fallback: _fallbackIcon),
    );
  }

  /// 스피너 파일을 못 읽을 때의 옛 점 아이콘(진행 중 색).
  static const Icon _fallbackIcon = Icon(AppIcons.circleDot, size: _iconSize, color: AppColors.primaryText);

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
