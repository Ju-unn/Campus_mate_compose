import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('라이트 테마는 Material 3 를 쓰고 캔버스 배경을 쓴다', () {
    final theme = AppTheme.light();

    expect(theme.useMaterial3, isTrue);
    expect(theme.scaffoldBackgroundColor, AppColors.canvas);
  });

  test('colorScheme 은 Material 기본 위젯용으로만 AppColors 를 채운다 (2026-09-15 결정)', () {
    final theme = AppTheme.light();

    expect(theme.colorScheme.primary, AppColors.primary);
    expect(theme.colorScheme.onPrimary, AppColors.onPrimary);
    expect(theme.colorScheme.surface, AppColors.canvas);
    expect(theme.colorScheme.onSurface, AppColors.ink);
    expect(theme.colorScheme.error, AppColors.error);
  });

  test('textTheme 15슬롯이 AppTypography 에 그대로 매핑된다', () {
    final textTheme = AppTheme.light().textTheme;

    // ThemeData 가 기본 색을 덧입히므로 크기·굵기·폰트만 비교한다 (색은 위젯이 AppColors 로 직접 지정)
    final slots = <String, (TextStyle?, TextStyle)>{
      'displayLarge': (textTheme.displayLarge, AppTypography.countdown),
      'displayMedium': (textTheme.displayMedium, AppTypography.display),
      'displaySmall': (textTheme.displaySmall, AppTypography.headline),
      'headlineLarge': (textTheme.headlineLarge, AppTypography.display),
      'headlineMedium': (textTheme.headlineMedium, AppTypography.headline),
      'headlineSmall': (textTheme.headlineSmall, AppTypography.navTitle),
      'titleLarge': (textTheme.titleLarge, AppTypography.title),
      'titleMedium': (textTheme.titleMedium, AppTypography.subtitle),
      'titleSmall': (textTheme.titleSmall, AppTypography.labelSmall),
      'bodyLarge': (textTheme.bodyLarge, AppTypography.body),
      'bodyMedium': (textTheme.bodyMedium, AppTypography.bodySmall),
      'bodySmall': (textTheme.bodySmall, AppTypography.caption),
      'labelLarge': (textTheme.labelLarge, AppTypography.label),
      'labelMedium': (textTheme.labelMedium, AppTypography.labelSmall),
      'labelSmall': (textTheme.labelSmall, AppTypography.badge),
    };

    expect(slots.length, 15, reason: 'Material 슬롯 15개를 모두 검사한다');
    slots.forEach((slot, pair) {
      final (actual, token) = pair;
      expect(actual?.fontSize, token.fontSize, reason: '$slot 크기');
      expect(actual?.fontWeight, token.fontWeight, reason: '$slot 굵기');
      expect(actual?.fontFamily, 'Pretendard', reason: '$slot 폰트');
    });
  });
}
