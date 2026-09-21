import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 하단 내비(DESIGN.md §8.9, pen `Migf0`). 탭 5개는 시안 그대로 두고,
/// 조각 4 가 채우는 것은 "오늘"·"대화" 둘뿐이다 — 나머지는 자리 화면으로 간다.
enum AppTab { main, today, community, chat, me }

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({required this.current, super.key});

  final AppTab current;

  static const _routes = <AppTab, String>{
    AppTab.main: AppRoutes.home,
    AppTab.today: AppRoutes.today,
    AppTab.community: AppRoutes.community,
    AppTab.chat: AppRoutes.conversations,
    AppTab.me: AppRoutes.myProfile,
  };

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: AppTab.values.indexOf(current),
      onDestinationSelected: (index) => context.go(_routes[AppTab.values[index]]!),
      backgroundColor: AppColors.canvas,
      indicatorColor: Colors.transparent,
      labelTextStyle: WidgetStatePropertyAll<TextStyle>(
        AppTypography.caption.copyWith(color: AppColors.muted),
      ),
      destinations: const [
        NavigationDestination(icon: Icon(AppIcons.house), label: '메인'),
        NavigationDestination(
          icon: Icon(AppIcons.heart),
          selectedIcon: Icon(AppIcons.heart, color: AppColors.primary),
          label: '오늘',
        ),
        NavigationDestination(icon: Icon(AppIcons.users), label: '커뮤니티'),
        NavigationDestination(icon: Icon(AppIcons.messageCircle), label: '대화'),
        NavigationDestination(icon: Icon(AppIcons.userRound), label: '나'),
      ],
    );
  }
}
