import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/matching/viewmodel/notification_settings_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 한 줄 = 서버 스위치 하나. "내 글의 새 댓글"(pen `KjGQd`)은 대응 컬럼이 없어 이번 조각에서 빠진다
/// (커뮤니티가 조각 6 에서 컬럼과 함께 만든다).
typedef _Row = ({String key, String title, String? note, IconData icon});

const _sections = <({String title, List<_Row> rows})>[
  (
    title: '매칭',
    rows: [
      (
        key: 'card_arrived',
        title: '오늘의 카드 도착',
        note: '매일 아침 7시 지급 알림',
        icon: AppIcons.heart
      ),
      (
        key: 'acceptance_received',
        title: '받은 수락',
        note: '상대가 나를 수락했을 때',
        icon: AppIcons.userPlus
      ),
      (
        key: 'match_made',
        title: '매칭 성립',
        note: '서로 수락해 대화가 열렸을 때',
        icon: AppIcons.badgeCheck
      ),
    ],
  ),
  (
    title: '대화',
    rows: [
      (key: 'new_message', title: '새 메시지', note: null, icon: AppIcons.messageCircle),
      (
        key: 'trust_reminder',
        title: '신뢰 확인 리마인드',
        note: '매칭 24시간 뒤 확인 안내',
        icon: AppIcons.timer
      ),
    ],
  ),
  (
    title: '지인 리뷰·커뮤니티',
    rows: [
      (key: 'new_friend_review', title: '새 지인 리뷰', note: null, icon: AppIcons.users),
    ],
  ),
  (
    title: '기타',
    rows: [
      (
        key: 'marketing',
        title: '혜택·이벤트 소식',
        note: '마케팅 정보 수신 동의',
        icon: AppIcons.bell
      ),
      (
        key: 'quiet_hours',
        title: '방해 금지 시간 (22:00 ~ 08:00)',
        note: null,
        icon: AppIcons.pause
      ),
    ],
  ),
];

/// 알림 설정(DESIGN.md 화면 16d, pen `NMgCa`).
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationSettingsViewModelProvider);
    final viewModel = ref.read(notificationSettingsViewModelProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text('알림', style: AppTypography.navTitle)),
      body: SafeArea(
        child: ListView(
          children: [
            for (final section in _sections) ...[
              _SectionHeader(section.title),
              for (final row in section.rows)
                SwitchListTile.adaptive(
                  value: state.preferences.valueOf(row.key),
                  onChanged: (value) => viewModel.toggle(row.key, value),
                  secondary: Icon(row.icon, color: AppColors.muted),
                  activeThumbColor: AppColors.primary,
                  title: Text(
                    row.title,
                    style: AppTypography.subtitle.copyWith(color: AppColors.ink),
                  ),
                  subtitle: row.note == null
                      ? null
                      : Text(
                          row.note!,
                          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
                        ),
                ),
            ],
            if (state.errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Text(
                  state.errorMessage!,
                  style: AppTypography.bodySmall.copyWith(color: AppColors.error),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              // 없으면 설정이 거짓말이 된다 — 카드 도착 알림만 조용한 시간 예외다(서버 `push.py`).
              child: Text(
                '오늘의 카드 도착 알림은 방해 금지 시간에도 보내드려요. 카드가 도착하는 시각이 아침 7시예요.',
                style: AppTypography.caption.copyWith(color: AppColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
      child: Text(title, style: AppTypography.bodySmall.copyWith(color: AppColors.muted)),
    );
  }
}
