import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
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

  test('textTheme 은 AppTypography 를 매핑한다', () {
    final theme = AppTheme.light();

    // ThemeData 가 기본 색을 덧입히므로 크기·굵기·자간만 비교한다 (색은 위젯이 AppColors 로 직접 지정)
    expect(theme.textTheme.headlineMedium?.fontSize, AppTypography.headline.fontSize);
    expect(theme.textTheme.headlineMedium?.fontWeight, AppTypography.headline.fontWeight);
    expect(theme.textTheme.bodyLarge?.fontSize, AppTypography.body.fontSize);
    expect(theme.textTheme.labelLarge?.fontSize, AppTypography.label.fontSize);
  });
}
