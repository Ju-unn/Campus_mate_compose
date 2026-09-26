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

/// 머티리얼 NavigationBar(높이 80·알약 표시·배지는 아이콘 위)로는 pen 모양이 안 나와 직접 그린다:
/// 윗선 1 + 바 60, 고른 탭은 아이콘·글자 모두 primary, 숫자 배지는 "대화" 글자 오른쪽.
class AppBottomNav extends ConsumerWidget {
  const AppBottomNav({required this.current, super.key});

  final AppTab current;

  static const _items = <(AppTab, IconData, String, String)>[
    (AppTab.main, AppIcons.house, '메인', AppRoutes.home),
    (AppTab.today, AppIcons.heart, '오늘', AppRoutes.today),
    (AppTab.community, AppIcons.users, '커뮤니티', AppRoutes.community),
    (AppTab.chat, AppIcons.messageCircle, '대화', AppRoutes.conversations),
    (AppTab.me, AppIcons.userRound, '나', AppRoutes.myProfile),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // §8.8: 뱃지는 대화 탭에만 붙고 숫자는 "수락 대기 + 안 읽은 메시지" 합이다.
    // 의미가 "나를 기다리는 사람 수" 하나라서 두 값을 나눠 보여주지 않는다.
    final badge = ref.watch(chatBadgeCountProvider);
    // Material 을 깔아야 탭의 InkWell 물결이 보인다 — DecoratedBox 위에서는 잉크가 그려지지 않는다.
    return Material(
      color: AppColors.canvas,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.hairlineSoft)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                for (final (tab, icon, label, route) in _items)
                  Expanded(
                    child: _NavItem(
                      icon: icon,
                      label: label,
                      isSelected: tab == current,
                      badge: tab == AppTab.chat ? badge : 0,
                      onTap: () => context.go(route),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.badge,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? AppColors.primary : AppColors.muted;
    // 아이콘·글자·숫자를 한 덩어리로 읽는다 — 토크백이 "대화", "3" 을 따로 읽으면 뜻이 흩어진다.
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: isSelected,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 글자를 키우면(DESIGN §11.2) 칸 폭 안에서 말줄임한다.
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.badge.copyWith(color: color),
                    ),
                  ),
                  if (badge > 0) ...[const SizedBox(width: 4), _CountBadge(count: badge)],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// pen `A6Xn1I` — 16×16 원, 두 자리부터는 옆으로 늘어난다.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    // 숫자만 읽으면 무슨 수인지 알 수 없다 — 뜻을 말로 주고 그림은 읽지 않는다.
    return Semantics(
      label: '안 읽음 $count개',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            count > 99 ? '99+' : '$count',
            style: AppTypography.badge.copyWith(color: AppColors.onPrimary, height: 1.2),
          ),
        ),
      ),
    );
  }
}
