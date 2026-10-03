import 'package:campus_mate/account/view/withdraw_sheets.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/consent/model/consent_links.dart';
import 'package:campus_mate/consent/model/open_url.dart';
import 'package:campus_mate/core/auth/confirm_sign_out.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/faq/viewmodel/faq_provider.dart';
import 'package:campus_mate/matching/viewmodel/notification_settings_view_model.dart';
import 'package:campus_mate/referral/view/invite_friends_sheet.dart';
import 'package:campus_mate/safety/view/contact_permission_sheets.dart';
import 'package:campus_mate/safety/view/safety_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 설정(DESIGN.md 화면 16, pen `lMDpY`). 섹션 머리글 + 카드 넷(매칭 · 하트 · 계정·정보 · 지원), 줄마다 3D 아이콘.
/// pen 맨 위 보유 하트 블록(`X4olk`)과 "하트 충전" 줄(`zlpeY`)은 스토어 화면이 없어 뺀다(대장 10-03, 결제 개편 때).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationSettingsViewModelProvider);
    // DESIGN §8.13: 받지도 못하고 캐시도 없을 때만 숨긴다. 받는 중에는 보인다 — 늦게 튀어나와 아래 줄이 밀리지 않게.
    final faq = ref.watch(faqProvider);
    final showFaq = faq.isLoading || (faq.value?.isNotEmpty ?? false);
    return Scaffold(
      appBar: AppBar(title: Text('설정', style: AppTypography.navTitle)),
      body: SafeArea(
        child: ListView(
          // pen `HM9xA` 위 12 · 좌우 16 · 섹션 사이 20.
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
          children: [
            _Section('매칭', [
              SwitchListTile.adaptive(
                // 꺼짐 = 일시중지다. 화면은 "활성화"를 묻고 서버에는 그 반대를 보낸다.
                value: !state.matchingPaused,
                onChanged: (value) =>
                    ref.read(notificationSettingsViewModelProvider.notifier).setPaused(!value),
                activeThumbColor: AppColors.primary,
                minTileHeight: 72,
                minVerticalPadding: 0,
                contentPadding: _rowPadding,
                horizontalTitleGap: AppSpacing.sm,
                secondary: const Icon3d(AppIcon3d.users, size: 22),
                title: Text('매칭 활성화', style: _titleStyle),
                subtitle: Text('잠시 쉬고 싶으면 꺼두세요', style: _noteStyle),
              ),
            ]),
            if (state.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  state.errorMessage!,
                  style: AppTypography.bodySmall.copyWith(color: AppColors.error),
                ),
              ),
            _sectionGap,
            _Section('하트', [
              _Row(
                icon: AppIcon3d.gift,
                title: '무료로 하트 모으기',
                onTap: () => context.push(AppRoutes.heartTasks),
              ),
              _Row(
                icon: AppIcon3d.users,
                title: '친구 초대',
                note: '내 추천 코드를 친구에게 보내요',
                onTap: () => showInviteFriendsSheet(context),
              ),
            ]),
            _sectionGap,
            _Section('계정·정보', [
              _Row(icon: AppIcon3d.userRound, title: '계정', onTap: () => context.push(AppRoutes.account)),
              _Row(
                icon: AppIcon3d.bell,
                title: '알림',
                onTap: () => context.push(AppRoutes.notificationSettings),
              ),
              _Row(icon: AppIcon3d.blockUser, title: '차단 목록', onTap: () => context.push(AppRoutes.blockList)),
              _Row(icon: AppIcon3d.contact, title: '연락처 차단', onTap: () => openContactBlocks(context, ref)),
            ]),
            _sectionGap,
            _Section('지원', [
              if (showFaq)
                _Row(
                  icon: AppIcon3d.help,
                  iconSize: 22,
                  title: '자주 묻는 질문',
                  onTap: () => context.push(AppRoutes.faq),
                ),
              _Row(icon: AppIcon3d.terms, title: '이용약관', onTap: () => _open(context, ref, termsLink)),
              _Row(
                icon: AppIcon3d.privacy,
                title: '개인정보처리방침',
                onTap: () => _open(context, ref, privacyPolicyLink),
              ),
              _Row(icon: AppIcon3d.logout, title: '로그아웃', onTap: () => confirmSignOut(context, ref)),
            ]),
            // 위험 영역(pen `VmUvb` padding [24,16,28,16] · `rlWDn`). 목록 줄이 아니라 목록 아래 단독 버튼이다(대장 결정 2) —
            // 좌우 16 은 목록 여백이 이미 준다.
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: 28),
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

  /// 약관은 기기 브라우저로 연다(약관 동의 02-c 와 같은 길). 못 열면 화면에 남고 안내만 띄운다.
  static Future<void> _open(BuildContext context, WidgetRef ref, Uri link) async {
    final messenger = ScaffoldMessenger.of(context);
    bool opened;
    try {
      opened = await ref.read(openUrlProvider)(link);
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      showSafetyToast(messenger, const UnknownFailure().toDisplayMessage(), icon: AppIcons.alertTriangle);
    }
  }
}

const _sectionGap = SizedBox(height: 20);

/// pen `K4uiNp` 줄 안쪽 좌우 14 · 제목 16/400 #222222 · 보조 글자 12 #6A6A6A.
const _rowPadding = EdgeInsets.symmetric(horizontal: 14);
final _titleStyle = AppTypography.body.copyWith(color: AppColors.ink);
final _noteStyle = AppTypography.caption.copyWith(color: AppColors.muted);

/// 섹션(pen `BOxgn` 등): 머리글 14/700 #6A6A6A → 8 → 카드(#F7F7F7 · r12 · 테두리 #DDDDDD).
/// 줄 사이 선(#EBEBEB)은 마지막 줄에서 지운다.
class _Section extends StatelessWidget {
  const _Section(this.title, this.rows);

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.xs,
      children: [
        Text(title, style: AppTypography.labelSmall.copyWith(color: AppColors.muted, fontWeight: FontWeight.w700)),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surfaceSoft,
            borderRadius: BorderRadius.circular(AppRadius.input),
          ),
          // 테두리는 위에 그린다 — 안쪽으로 1 씩 밀리지 않아 줄이 카드 폭 그대로다(pen 줄 폭 = 카드 폭).
          foregroundDecoration: BoxDecoration(
            border: Border.all(color: AppColors.hairline),
            borderRadius: BorderRadius.circular(AppRadius.input),
          ),
          child: Column(
            children: [
              for (final (i, row) in rows.indexed)
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: i == rows.length - 1
                        ? null
                        : const Border(bottom: BorderSide(color: AppColors.hairlineSoft)),
                  ),
                  // 잉크는 가장 가까운 Material 에 그린다 — Scaffold 에 그리면 목록을 밀어도 눌림 테두리가 제자리에 뜬다(COMMON §4-2).
                  child: Material(type: MaterialType.transparency, child: row),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 설정 줄(pen `K4uiNp`): 52(설명이 있으면 72) · 3D 아이콘 24 → 12 → 제목, 오른쪽 chevron-right 20 #6A6A6A.
class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, required this.onTap, this.iconSize = 24, this.note});

  final AppIcon3d icon;
  final double iconSize;
  final String title;
  final String? note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      // 높이는 최소값만 건다 — 글자를 키우면 줄이 따라 커진다.
      minTileHeight: note == null ? 52 : 72,
      minVerticalPadding: 0,
      contentPadding: _rowPadding,
      horizontalTitleGap: AppSpacing.sm,
      minLeadingWidth: 0,
      leading: Icon3d(icon, size: iconSize),
      title: Text(title, style: _titleStyle),
      subtitle: note == null ? null : Text(note!, style: _noteStyle),
      trailing: const Icon(AppIcons.chevronRight, size: 20, color: AppColors.muted),
      onTap: onTap,
    );
  }
}
