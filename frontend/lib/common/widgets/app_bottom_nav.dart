import 'package:campus_mate/chat/viewmodel/conversations_view_model.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 하단 내비(DESIGN.md §8.9, pen `Migf0`). 탭 5개는 시안 그대로 두고,
/// 조각 4 가 채우는 것은 "오늘"·"대화" 둘뿐이다 — 나머지는 자리 화면으로 간다.
enum AppTab { main, today, community, chat, me }

class AppBottomNav extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    // §8.8: 뱃지는 대화 탭에만 붙고 숫자는 "수락 대기 + 안 읽은 메시지" 합이다.
    // 의미가 "나를 기다리는 사람 수" 하나라서 두 값을 나눠 보여주지 않는다.
    final badge = ref.watch(chatBadgeCountProvider);
    return NavigationBar(
      selectedIndex: AppTab.values.indexOf(current),
      onDestinationSelected: (index) => context.go(_routes[AppTab.values[index]]!),
      backgroundColor: AppColors.canvas,
      indicatorColor: Colors.transparent,
      labelTextStyle: WidgetStatePropertyAll<TextStyle>(
        AppTypography.caption.copyWith(color: AppColors.muted),
      ),
      destinations: [
        const NavigationDestination(icon: Icon(AppIcons.house), label: '메인'),
        const NavigationDestination(
          icon: Icon(AppIcons.heart),
          selectedIcon: Icon(AppIcons.heart, color: AppColors.primary),
          label: '오늘',
        ),
        const NavigationDestination(icon: Icon(AppIcons.users), label: '커뮤니티'),
        NavigationDestination(
          icon: badge > 0
              ? Badge(
                  backgroundColor: AppColors.primary,
                  textStyle: AppTypography.badge.copyWith(color: AppColors.onPrimary),
                  label: Text(badge > 99 ? '99+' : '$badge'),
                  child: const Icon(AppIcons.messageCircle),
                )
              : const Icon(AppIcons.messageCircle),
          label: '대화',
        ),
        const NavigationDestination(icon: Icon(AppIcons.userRound), label: '나'),
      ],
    );
  }
}
