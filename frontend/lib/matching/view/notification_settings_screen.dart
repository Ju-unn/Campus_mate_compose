import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/push/push_provider.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/matching/viewmodel/notification_settings_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 한 줄 = 서버 스위치 하나. "내 글의 새 댓글"(pen `KjGQd`)은 대응 컬럼이 없어 이번 조각에서 빠진다
/// (커뮤니티가 조각 6 에서 컬럼과 함께 만든다).
typedef _Row = ({String key, String title, String? note, AppIcon3d icon});

const _sections = <({String title, List<_Row> rows})>[
  (
    title: '매칭',
    rows: [
      (
        key: 'card_arrived',
        title: '오늘의 카드 도착',
        note: '매일 아침 7시 지급 알림',
        icon: AppIcon3d.layers
      ),
      (
        key: 'acceptance_received',
        title: '받은 수락',
        note: '상대가 나를 수락했을 때',
        icon: AppIcon3d.heart
      ),
      (
        key: 'match_made',
        title: '매칭 성립',
        note: '서로 수락해 대화가 열렸을 때',
        icon: AppIcon3d.users
      ),
    ],
  ),
  (
    title: '대화',
    rows: [
      (key: 'new_message', title: '새 메시지', note: null, icon: AppIcon3d.chat),
      (
        key: 'trust_reminder',
        title: '신뢰 확인 리마인드',
        note: '매칭 24시간 뒤 확인 안내',
        icon: AppIcon3d.clock
      ),
    ],
  ),
  (
    title: '지인 리뷰·커뮤니티',
    rows: [
      (key: 'new_friend_review', title: '새 지인 리뷰', note: null, icon: AppIcon3d.heartHandshake),
    ],
  ),
  (
    title: '기타',
    rows: [
      (
        key: 'marketing',
        title: '혜택·이벤트 소식',
        note: '마케팅 정보 수신 동의',
        icon: AppIcon3d.megaphone
      ),
      (
        key: 'quiet_hours',
        title: '방해 금지 시간 (22:00 ~ 08:00)',
        note: null,
        icon: AppIcon3d.moon
      ),
    ],
  ),
];

/// 알림 설정(DESIGN.md 화면 16d, pen `NMgCa`).
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends ConsumerState<NotificationSettingsScreen> {
  // 기기 설정에서 켜고 돌아오면 안내가 바로 사라져야 한다 — 돌아올 때마다 다시 읽는다.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => ref.invalidate(deviceNotificationsPermittedProvider));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 읽는 중 · 못 읽음은 켜짐으로 본다 — 확실할 때만 안내를 띄운다.
    final deviceOff = ref.watch(deviceNotificationsPermittedProvider).value == false;
    final state = ref.watch(notificationSettingsViewModelProvider);
    final viewModel = ref.read(notificationSettingsViewModelProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text('알림', style: AppTypography.navTitle)),
      body: SafeArea(
        child: ListView(
          children: [
            if (deviceOff)
              _DeviceNotificationsOff(
                onOpen: () => ref.read(pushMessagingProvider).openNotificationSettings(),
              ),
            for (final section in _sections) ...[
              _SectionHeader(section.title),
              for (final row in section.rows)
                // 잉크는 가장 가까운 Material 에 그린다 — Scaffold 에 그리면 목록을 밀어도 눌림 테두리가 제자리에 뜬다(COMMON §4-2).
                Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile.adaptive(
                    value: state.preferences.valueOf(row.key),
                    onChanged: (value) => viewModel.toggle(row.key, value),
                    secondary: Icon3d(row.icon, size: 24),
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

/// 16d-1(pen `fnGUA`). 앱 스위치가 다 켜져 있어도 기기에서 막으면 알림이 하나도 안 온다(A9).
/// 목록 틀 `Znioc` 위 12 · 좌우 16 · 간격 20, 안내 상자 `gvjXK`, 버튼 `WTUbC`(기본 버튼 52/14).
class _DeviceNotificationsOff extends StatelessWidget {
  const _DeviceNotificationsOff({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 20,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.primaryWash,
              borderRadius: BorderRadius.circular(AppRadius.input),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              // pen 문구 "기기 설정에서 켜 주세요" 에 "알림을 눌러" 를 더했다 — 버튼이 알림 화면이 아니라
              // 앱 설정 화면에 내려 준다(대장 10-03 가).
              child: Text(
                '기기 알림이 꺼져 있어요. 알림을 받으려면 기기 설정에서 알림을 눌러 켜 주세요',
                style: AppTypography.bodySmall.copyWith(color: AppColors.body, height: 1.5),
              ),
            ),
          ),
          AppButton(label: '기기 알림 설정 열기', onPressed: onOpen),
        ],
      ),
    );
  }
}
