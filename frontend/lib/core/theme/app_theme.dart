import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 토큰을 조립해 앱 전역 테마를 만든다.
///
/// `colorScheme` 은 Material 기본 위젯(예: 기본 버튼) 용으로만 채운다.
/// 화면 코드는 색은 [AppColors], 글자는 [AppTypography] 를 직접 읽는다
/// (2026-09-15 사용자 결정). 다크 모드는 MVP 범위에서 제외한다 (DESIGN §2.7).
abstract final class AppTheme {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: _lightColorScheme(),
      scaffoldBackgroundColor: AppColors.canvas,
      textTheme: _textTheme(),
      // 본문이 앱바 밑으로 스크롤돼도 앱바는 흰색 그대로다 — M3 scrolledUnder 의 분홍 물듦 · 그림자를 끈다(pen 앱바는 늘 흰색).
      appBarTheme: const AppBarTheme(scrolledUnderElevation: 0, surfaceTintColor: Colors.transparent),
    );
  }

  static ColorScheme _lightColorScheme() {
    return ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      surface: AppColors.canvas,
      onSurface: AppColors.ink,
      outline: AppColors.outline,
      error: AppColors.error,
      onError: AppColors.onPrimary,
      scrim: AppColors.scrim,
    );
  }

  static TextTheme _textTheme() {
    return const TextTheme(
      displayLarge: AppTypography.countdown,
      displayMedium: AppTypography.display,
      displaySmall: AppTypography.headline,
      headlineLarge: AppTypography.display,
      headlineMedium: AppTypography.headline,
      headlineSmall: AppTypography.navTitle,
      titleLarge: AppTypography.title,
      titleMedium: AppTypography.subtitle,
      titleSmall: AppTypography.labelSmall,
      bodyLarge: AppTypography.body,
      bodyMedium: AppTypography.bodySmall,
      bodySmall: AppTypography.caption,
      labelLarge: AppTypography.label,
      labelMedium: AppTypography.labelSmall,
      labelSmall: AppTypography.badge,
    );
  }
}
