import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 앱 진입 직후 잠시 보이는 화면(pen `jXJSY`). 스피너는 두지 않는다(DESIGN.md §13-3).
/// 마스코트·부제는 2026-09-23 사용자 결정으로 pen 대로 넣었다.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/mascot-female.png', width: 96, height: 96),
            const SizedBox(height: AppSpacing.md),
            Text('CampusMate', style: AppTypography.display.copyWith(color: AppColors.primary)),
            const SizedBox(height: AppSpacing.md),
            Text('하루 한 사람, 같은 캠퍼스에서', style: AppTypography.body.copyWith(color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}

/// 아직 만들지 않은 탭(지금은 커뮤니티). 하단 내비는 5탭을 그리므로 갈 곳은 있어야 한다.
///
/// 톱니는 두지 않는다 — 설정(16)으로 들어가는 곳은 15 내 프로필(`r8oJc`) 앱바의 톱니
/// (`ffOFL` 안 `C7teyl`) 하나뿐이고, 그 화면이 `MyProfileScreen` 이다.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({required this.tab, super.key});

  final AppTab tab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: const Center(child: Text('곧 만나요', style: AppTypography.headline)),
      bottomNavigationBar: AppBottomNav(current: tab),
    );
  }
}
