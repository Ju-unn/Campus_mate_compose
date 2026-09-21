import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// DESIGN.md §8.3 버튼 5종. 화면은 [variant] 와 [onPressed](null = 비활성)만
/// 고르고, 색·라운드·라벨 크기는 여기서만 정한다.
enum AppButtonVariant { primary, secondary, text, danger, dangerStrong }

class AppButton extends StatelessWidget {
  const AppButton({
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.height,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;

  /// 목록 안 인라인 버튼만 다른 높이를 쓴다(§8.3 "인라인 버튼 높이 변형" — 수락함 행이 44dp).
  /// 비워 두면 전체 폭 버튼 규격(56, text variant 는 48)이다.
  final double? height;

  bool get _isTextVariant => variant == AppButtonVariant.text;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: _styleFor(height ?? (_isTextVariant ? 48 : 56)),
      child: Text(label, style: _isTextVariant ? AppTypography.labelSmall : AppTypography.label),
    );
  }

  ButtonStyle _styleFor(double height) {
    final base = ElevatedButton.styleFrom(
      minimumSize: Size(double.infinity, height),
      maximumSize: Size(double.infinity, height),
      padding: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
    );
    return base.copyWith(
      backgroundColor: _backgroundColor(),
      foregroundColor: _foregroundColor(),
      overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
    );
  }

  WidgetStateProperty<Color> _backgroundColor() {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return _isTextVariant ? Colors.transparent : AppColors.primaryDisabled;
      }
      if (states.contains(WidgetState.pressed)) {
        return variant == AppButtonVariant.primary
            ? AppColors.primaryPressed
            : AppColors.surfaceSoft;
      }
      return _idleBackground();
    });
  }

  Color _idleBackground() {
    return switch (variant) {
      AppButtonVariant.primary => AppColors.primary,
      AppButtonVariant.secondary => AppColors.primaryDisabled,
      AppButtonVariant.text => Colors.transparent,
      AppButtonVariant.danger => AppColors.primaryDisabled,
      AppButtonVariant.dangerStrong => AppColors.error,
    };
  }

  WidgetStateProperty<Color> _foregroundColor() {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return AppColors.disabled;
      }
      return _idleForeground();
    });
  }

  Color _idleForeground() {
    return switch (variant) {
      AppButtonVariant.primary => AppColors.onPrimary,
      AppButtonVariant.secondary => AppColors.ink,
      AppButtonVariant.text => AppColors.primaryText,
      AppButtonVariant.danger => AppColors.error,
      AppButtonVariant.dangerStrong => AppColors.onPrimary,
    };
  }
}
