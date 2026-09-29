import 'package:campus_mate/account/view/withdraw_sheets.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/matching/viewmodel/notification_settings_view_model.dart';
import 'package:campus_mate/referral/view/invite_friends_sheet.dart';
import 'package:campus_mate/safety/view/contact_permission_sheets.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
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
                leading: const Icon(AppIcons.gift, color: AppColors.muted),
                title: Text('무료로 하트 모으기', style: AppTypography.subtitle.copyWith(color: AppColors.ink)),
                trailing: const Icon(AppIcons.chevronRight, color: AppColors.muted),
                onTap: () => context.push(AppRoutes.heartTasks),
              ),
              ListTile(
                leading: const Icon(AppIcons.userPlus, color: AppColors.muted),
                title: Text('친구 초대', style: AppTypography.subtitle.copyWith(color: AppColors.ink)),
                // pen `b1fvA` 설명 줄. 글자 모양은 이웃 줄(매칭 활성화)에 맞춘다 — 16 전체 pen 맞추기는 백로그 70.
                subtitle: Text(
                  '내 추천 코드를 친구에게 보내요',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
                ),
                trailing: const Icon(AppIcons.chevronRight, color: AppColors.muted),
                onTap: () => showInviteFriendsSheet(context),
              ),
              ListTile(
                leading: const Icon(AppIcons.userRound, color: AppColors.muted),
                title: Text('계정', style: AppTypography.subtitle.copyWith(color: AppColors.ink)),
                trailing: const Icon(AppIcons.chevronRight, color: AppColors.muted),
                onTap: () => context.push(AppRoutes.account),
              ),
              ListTile(
                leading: const Icon(AppIcons.bell, color: AppColors.muted),
                title: Text('알림', style: AppTypography.subtitle.copyWith(color: AppColors.ink)),
                trailing: const Icon(AppIcons.chevronRight, color: AppColors.muted),
                onTap: () => context.push(AppRoutes.notificationSettings),
              ),
              ListTile(
                leading: const Icon(AppIcons.userX, color: AppColors.muted),
                title: Text('차단 목록', style: AppTypography.subtitle.copyWith(color: AppColors.ink)),
                trailing: const Icon(AppIcons.chevronRight, color: AppColors.muted),
                onTap: () => context.push(AppRoutes.blockList),
              ),
              ListTile(
                leading: const Icon(AppIcons.contactRound, color: AppColors.muted),
                title: Text('연락처 차단', style: AppTypography.subtitle.copyWith(color: AppColors.ink)),
                trailing: const Icon(AppIcons.chevronRight, color: AppColors.muted),
                onTap: () => openContactBlocks(context, ref),
              ),
              ListTile(
                leading: const Icon(AppIcons.logOut, color: AppColors.muted),
                title: Text('로그아웃', style: AppTypography.subtitle.copyWith(color: AppColors.ink)),
                trailing: const Icon(AppIcons.chevronRight, color: AppColors.muted),
                onTap: () => _confirmSignOut(context, ref),
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
            // 위험 영역(pen `VmUvb` padding [24,16,28,16] · `rlWDn`). 목록 줄이 아니라 목록 아래 단독 버튼이다(대장 결정 2) —
            // AppButton 은 자기 Material 에 잉크를 그려 위 목록 규칙(투명 Material)이 필요 없다.
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.lg, AppSpacing.md, 28),
              child: AppButton(
                label: '탈퇴하기',
                variant: AppButtonVariant.danger,
                onPressed: () => showWithdrawSheets(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 16g(pen `ZkOEb`). 틀이 안전 확인 시트(`aCTy1`)와 같아 그대로 쓴다. 확인하면 시트가 먼저 닫히고,
  /// 로그아웃이 끝나면 라우터가 로그인 화면으로 보낸다 — 여기서 이동하지 않는다.
  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final signOut = ref.read(signOutProvider);
    final confirmed = await showSafetyConfirmSheet(
      context,
      title: '로그아웃할까요?',
      description: '다시 로그인하려면 학교 이메일로 인증 코드를 한 번 더 받아야 해요.',
      confirmLabel: '로그아웃',
    );
    if (confirmed) {
      await signOut();
    }
  }
}
