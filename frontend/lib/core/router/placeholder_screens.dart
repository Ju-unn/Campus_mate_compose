import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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

/// 아직 만들지 않은 탭(메인 09b·커뮤니티·나). 하단 내비는 5탭을 그리므로 갈 곳은 있어야 한다.
///
/// "나" 탭에만 톱니를 둔다 — pen 에서 설정(16)으로 들어가는 곳은 15 내 프로필(`r8oJc`)
/// 앱바의 톱니(`ffOFL` 안 `C7teyl`) 하나뿐이다. **15 를 만들면 그리로 옮긴다.**
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({required this.tab, super.key});

  final AppTab tab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: tab != AppTab.me
          ? null
          : AppBar(
              actions: [
                IconButton(
                  tooltip: '설정',
                  icon: const Icon(AppIcons.settings),
                  onPressed: () => context.push(AppRoutes.settings),
                ),
              ],
            ),
      body: const Center(child: Text('곧 만나요', style: AppTypography.headline)),
      bottomNavigationBar: AppBottomNav(current: tab),
    );
  }
}
