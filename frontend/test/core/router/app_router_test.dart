import 'package:campus_mate/core/router/app_router.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('로그인하지 않으면 로그인 화면이 보인다', (tester) async {
    final router = AppRouter.create(isAuthenticated: false);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('대학 이메일로 시작해요'), findsOneWidget);
  });

  testWidgets('로그인하면 홈 화면이 보인다', (tester) async {
    final router = AppRouter.create(isAuthenticated: true);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('오늘의 카드'), findsOneWidget);
  });
}
