import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 실폰(커뮤니티 글쓰기): 키보드로 본문이 앱바 밑으로 밀리면 M3 scrolledUnder 가 앱바를 분홍으로 물들였다.
  // pen 앱바는 늘 흰색 — 화면마다 막지 않고 테마 한 곳에서 막는다.
  for (final (name, appBar) in [
    ('색을 안 정한 앱바', AppBar(title: const Text('제목'))),
    ('캔버스 색을 정한 앱바', AppBar(backgroundColor: AppColors.canvas, title: const Text('제목'))),
  ]) {
    testWidgets('$name 는 본문이 밑으로 스크롤돼도 흰색 그대로다(물듦 · 그림자 없음)', (tester) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: Scaffold(
          appBar: appBar,
          body: ListView(children: [for (var i = 0; i < 60; i++) SizedBox(height: 40, child: Text('줄 $i'))]),
        ),
      ));
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();

      final material = tester.widget<Material>(find.descendant(of: find.byType(AppBar), matching: find.byType(Material)).first);
      final shown = ElevationOverlay.applySurfaceTint(material.color!, material.surfaceTintColor, material.elevation);
      expect(shown, AppColors.canvas);
      expect(material.elevation, 0);
      // 누가 앱바에 높이를 줘도 분홍으로 물들지 않게 물듦 색 자체를 끈다.
      expect(material.surfaceTintColor, Colors.transparent);
    });
  }

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
