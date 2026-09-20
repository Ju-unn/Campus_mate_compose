import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/core/router/app_router.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 이 파일은 경로·화면 연결만 본다. 게이트별 이동 규칙은 auth_redirect_test 가 맡는다.
VerificationGate _passedGate() => VerificationGate.complete;
OnboardingStep _passedStep() => OnboardingStep.complete;

void main() {
  testWidgets('로그인하지 않으면 로그인 화면이 보인다', (tester) async {
    final router = AppRouter.create(
      isAuthenticated: () => false,
      verificationGate: _passedGate,
      onboardingStep: _passedStep,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('대학 이메일로 시작해요'), findsOneWidget);
  });

  testWidgets('로그인하면 홈 화면이 보인다', (tester) async {
    final router = AppRouter.create(
      isAuthenticated: () => true,
      verificationGate: _passedGate,
      onboardingStep: _passedStep,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('오늘의 카드'), findsOneWidget);
  });

  testWidgets('extra 없이 인증코드 화면에 진입하면 로그인 화면으로 보낸다', (tester) async {
    final router = AppRouter.create(
      isAuthenticated: () => false,
      verificationGate: _passedGate,
      onboardingStep: _passedStep,
    );
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router, theme: AppTheme.light())),
    );
    router.go(AppRoutes.verifyCode);
    await tester.pumpAndSettle();

    expect(find.text('대학 이메일로 시작해요'), findsOneWidget);
  });
}
