import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:flutter/material.dart';

/// 웹 토큰을 조립한 테마. 화면 코드는 색 · 글자를 토큰에서 직접 읽고, 여기는 Material 기본 위젯 몫만 채운다.
abstract final class AdminTheme {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      fontFamily: AdminTypography.family,
      // 데스크톱 기본(compact)은 컨트롤 높이를 줄인다 — pen 은 44 기준이다.
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: AdminColors.canvas,
      colorScheme: const ColorScheme.light(
        primary: AdminColors.primary,
        onPrimary: AdminColors.onPrimary,
        surface: AdminColors.surface,
        onSurface: AdminColors.ink,
        outline: AdminColors.outline,
        error: AdminColors.danger,
        onError: AdminColors.onPrimary,
        scrim: AdminColors.scrim,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AdminColors.primary),
    );
  }
}
