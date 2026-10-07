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
        icon: AppIcon3d.layers,
      ),
      (
        key: 'acceptance_received',
        title: '받은 수락',
        note: '상대가 나를 수락했을 때',
        icon: AppIcon3d.heart,
      ),
      (
        key: 'match_made',
        title: '매칭 성립',
        note: '서로 수락해 대화가 열렸을 때',
        icon: AppIcon3d.users,
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
        icon: AppIcon3d.clock,
      ),
    ],
  ),
  (
    title: '지인 리뷰·커뮤니티',
    rows: [
      (
        key: 'new_friend_review',
        title: '새 지인 리뷰',
        note: null,
        icon: AppIcon3d.heartHandshake,
      ),
    ],
  ),
  (
    title: '기타',
    rows: [
      (
        key: 'marketing',
        title: '혜택·이벤트 소식',
        note: '마케팅 정보 수신 동의',
        icon: AppIcon3d.megaphone,
      ),
      (
        key: 'quiet_hours',
        title: '방해 금지 시간 (22:00 ~ 08:00)',
        note: null,
        icon: AppIcon3d.moon,
      ),
    ],
  ),
];

/// 알림 설정(DESIGN.md 화면 16d, pen `NMgCa`).
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  // 기기 설정에서 켜고 돌아오면 안내가 바로 사라져야 한다 — 돌아올 때마다 다시 읽는다.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(deviceNotificationsPermittedProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 읽는 중 · 못 읽음은 켜짐으로 본다 — 확실할 때만 안내를 띄운다.
    final deviceOff =
        ref.watch(deviceNotificationsPermittedProvider).value == false;
    final state = ref.watch(notificationSettingsViewModelProvider);
    final viewModel = ref.read(notificationSettingsViewModelProvider.notifier);
    return Scaffold(
      // pen `ceDU6`.
      appBar: AppBar(title: Text('알림', style: AppTypography.navTitle)),
      body: SafeArea(
        child: ListView(
          // 목록 틀 `Znioc` — 위 12 · 좌우 16 · 아래 24, 덩어리 사이 20(계정 16e `n8lZI` 와 같다).
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.lg,
          ),
          children: [
            if (deviceOff) ...[
              _DeviceNotificationsOff(
                onOpen: () =>
                    ref.read(pushMessagingProvider).openNotificationSettings(),
              ),
              const SizedBox(height: _gap),
            ],
            for (final section in _sections) ...[
              _SectionHeader(section.title),
              const SizedBox(height: AppSpacing.xs),
              // 카드 `kX4oK` · `LvHyT` · `URYwe` · `YAt0F` — #F7F7F7, 테두리 #DDDDDD, 모서리 12.
              _SectionCard(
                children: [
                  for (final row in section.rows)
                    // 잉크는 가장 가까운 Material 에 그린다 — Scaffold 에 그리면 목록을 밀어도 눌림 테두리가 제자리에 뜬다(COMMON §4-2).
                    _RowBox(
                      minHeight: row.note == null ? _rowHeight : _noteRowHeight,
                      // 아래 선: 64 줄은 모두, 52 줄은 카드의 마지막 줄만 뺀다(pen 값은 64 줄만 읽혔고 52 줄은 스크린샷으로 본 것 — 불확실).
                      divider: row.note != null || row != section.rows.last,
                      child: Material(
                        type: MaterialType.transparency,
                        // 기본 글 자리(leading 40 · gap 16)를 pen 값(아이콘 22 · gap 12)으로 — SwitchListTile 은 두 값을 못 받아 테마로 준다.
                        child: ListTileTheme(
                          data: const ListTileThemeData(
                            horizontalTitleGap: _titleGap,
                            minLeadingWidth: _iconSize,
                          ),
                          child: SwitchListTile.adaptive(
                            value: state.preferences.valueOf(row.key),
                            onChanged: (value) =>
                                viewModel.toggle(row.key, value),
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: _rowPadding,
                            ),
                            secondary: Icon3d(row.icon, size: _iconSize),
                            activeThumbColor: AppColors.onPrimary,
                            activeTrackColor: AppColors.primary,
                            inactiveThumbColor: AppColors.onPrimary,
                            inactiveTrackColor: _trackOff,
                            trackOutlineColor: const WidgetStatePropertyAll(
                              Colors.transparent,
                            ),
                            // 라벨 16/normal #222222(pen `jtLpv` 등), 설명 12/normal #6A6A6A 줄 높이 1.4.
                            title: Text(
                              row.title,
                              style: AppTypography.body.copyWith(
                                color: AppColors.ink,
                              ),
                            ),
                            subtitle: row.note == null
                                ? null
                                : Text(
                                    row.note!,
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.muted,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: _gap),
            ],
            if (state.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  state.errorMessage!,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ),
            // 없으면 설정이 거짓말이 된다 — 카드 도착 알림만 조용한 시간 예외다(서버 `push.py`).
            Text(
              '오늘의 카드 도착 알림은 방해 금지 시간에도 보내드려요. 카드가 도착하는 시각이 아침 7시예요.',
              style: AppTypography.caption.copyWith(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// pen 덩어리 사이 간격 20(`Znioc` gap).
const double _gap = 20;

/// 카드 줄 높이 — 부연 글이 있으면 64(`kX4oK` 줄), 없으면 52(`LvHyT` 144 − 머리 28 = 줄 64 + 52). pen 은 최소값이라 글자를 키우면 늘어난다.
const double _noteRowHeight = 64;
const double _rowHeight = 52;

/// 줄 좌우 여백 — 계정 16e 줄(`_InfoRow`)과 같은 14(pen 은 이 화면 줄의 여백을 안 줬다: 값 필요).
const double _rowPadding = 14;

/// 3D 아이콘 크기 — pen 인스턴스 22×22(`jtLpv` · `b6Be6` · `JTdOw` · `ZkbzW` · `CWpHt` · `BLXJu` · `cjlyY` · `xDcmZ`).
const double _iconSize = 22;

/// 아이콘과 글 사이 간격 12(pen gap).
const double _titleGap = 12;

/// 스위치 색 — 켜짐 #FF385C · 꺼짐 #DDDDDD · 손잡이 흰색(pen 스위치 48×28 · 손잡이 20).
const Color _trackOff = AppColors.hairline;

/// 섹션 머리 — 14/700 muted, 줄 높이 20(계정 16e 의 머리와 같다). 아래 간격 8 은 쓰는 쪽이 둔다(머리 20 + 8 = pen 28).
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: AppTypography.bodySmall.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.muted,
        height: 20 / 14,
      ),
    );
  }
}

/// 카드 틀 — 계정 16e `_InfoCard` 와 같은 모양(#F7F7F7 · 테두리 #DDDDDD · 모서리 12).
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceSoft,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.input),
        side: const BorderSide(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

/// 줄 하나 — 최소 높이와 아래 가는 선([divider]).
class _RowBox extends StatelessWidget {
  const _RowBox({
    required this.minHeight,
    required this.divider,
    required this.child,
  });

  final double minHeight;
  final bool divider;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        border: divider
            ? const Border(bottom: BorderSide(color: AppColors.hairlineSoft))
            : null,
      ),
      child: child,
    );
  }
}

/// 16d-1(pen `fnGUA`). 앱 스위치가 다 켜져 있어도 기기에서 막으면 알림이 하나도 안 온다(A9).
/// 안내 상자 `gvjXK`(328×72) · 버튼 `WTUbC`(328×52) 사이 간격 20 — 바깥 여백은 목록 틀 `Znioc` 가 준다.
class _DeviceNotificationsOff extends StatelessWidget {
  const _DeviceNotificationsOff({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: _gap,
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
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.body,
                height: 1.5,
              ),
            ),
          ),
        ),
        AppButton(label: '기기 알림 설정 열기', onPressed: onOpen),
      ],
    );
  }
}
