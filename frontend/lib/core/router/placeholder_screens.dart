import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 앱 진입 직후 잠시 보이는 화면. "CampusMate" 문구만 두고 스피너는 두지 않는다
/// (DESIGN.md §13-3, 2026-09-15 사용자 결정). 실제 세션 확인 로직은 조각 1에서 채운다.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('CampusMate', style: AppTypography.headline),
      ),
    );
  }
}

/// 로그인 화면 자리. 실제 인증은 조각 1에서 구현한다.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: const Text('로그인', style: AppTypography.headline),
        ),
      ),
    );
  }
}

/// 홈 화면 자리. 오늘의 카드는 조각 4에서 구현한다.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text('오늘의 카드', style: AppTypography.headline),
      ),
    );
  }
}
