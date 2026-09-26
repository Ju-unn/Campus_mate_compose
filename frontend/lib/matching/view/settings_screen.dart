import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/matching/viewmodel/notification_settings_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 설정(DESIGN.md 화면 16, pen `lMDpY`). 조각 4 가 소유한 두 줄만 그린다 —
/// 하트·차단·약관·탈퇴는 조각 5~7 이 각자 붙인다.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationSettingsViewModelProvider);
    return Scaffold(
      appBar: AppBar(title: Text('설정', style: AppTypography.navTitle)),
      body: SafeArea(
        child: ListView(
          // 잉크는 가장 가까운 Material 에 그린다 — Scaffold 에 그리면 목록을 밀어도 눌림 테두리가 제자리에 뜬다(COMMON §4-2).
          // 줄마다 투명 Material 을 주되, 새 줄도 이 목록에 넣기만 하면 저절로 감싸지게 한 곳에서 준다.
          children: [
            for (final row in [
              SwitchListTile.adaptive(
                // 꺼짐 = 일시중지다. 화면은 "활성화"를 묻고 서버에는 그 반대를 보낸다.
                value: !state.matchingPaused,
                onChanged: (value) =>
                    ref.read(notificationSettingsViewModelProvider.notifier).setPaused(!value),
                activeThumbColor: AppColors.primary,
                title: Text('매칭 활성화', style: AppTypography.subtitle.copyWith(color: AppColors.ink)),
                subtitle: Text(
                  '잠시 쉬고 싶으면 꺼두세요',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
                ),
              ),
              ListTile(
                leading: const Icon(AppIcons.bell, color: AppColors.muted),
                title: Text('알림', style: AppTypography.subtitle.copyWith(color: AppColors.ink)),
                trailing: const Icon(AppIcons.chevronRight, color: AppColors.muted),
                onTap: () => context.push(AppRoutes.notificationSettings),
              ),
              if (state.errorMessage != null)
                ListTile(
                  title: Text(
                    state.errorMessage!,
                    style: AppTypography.bodySmall.copyWith(color: AppColors.error),
                  ),
                ),
            ])
              Material(type: MaterialType.transparency, child: row),
          ],
        ),
      ),
    );
  }
}
