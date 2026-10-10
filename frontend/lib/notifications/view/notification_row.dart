import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/community/view/poll_time.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/notifications/model/app_notification.dart';
import 'package:flutter/material.dart';

/// 테스트가 pen 크기를 재는 데 쓰는 자리 표시.
ValueKey<String> notificationRowKey(String id) => ValueKey('notification-row-$id');
const Key notificationIconCircleKey = ValueKey('notification-icon-circle');
const Key notificationUnreadDotKey = ValueKey('notification-unread-dot');

/// 종류별 3D 그림(pen 마스터 `70. Item · Notification` 의 3D Icon `OaDey` 를 종류마다 Replace).
/// 카드 도착 `wAQtn` · 대화 신청 `Lua1H` · 매칭 `zxXQG` · 지인 리뷰 `dAIki` · 학생증 결과 `Trtii` · 밤사이 묶음 `WyOg1`.
/// 모르는 종류는 밤사이 묶음과 같은 알림 종이다.
AppIcon3d notificationIcon(NotificationKind kind) => switch (kind) {
      NotificationKind.cardArrived => AppIcon3d.layers,
      NotificationKind.chatRequest => AppIcon3d.chat,
      NotificationKind.matchMade => AppIcon3d.heart,
      NotificationKind.friendReview => AppIcon3d.heartHandshake,
      NotificationKind.verificationResult => AppIcon3d.badgeCheck,
      NotificationKind.nightDigest || NotificationKind.other => AppIcon3d.bell,
    };

/// 알림함 한 줄. pen `Item · Notification` 마스터 두 변형(안 읽음 `VAzRr` · 읽음 `iVIkt`).
/// 읽음은 색만이 아니라 제목 굵기(700 / 400)와 오른쪽 점, 낭독 문구("안 읽은 알림")로도 알린다.
class NotificationRow extends StatelessWidget {
  const NotificationRow({
    required this.item,
    required this.now,
    required this.onTap,
    this.showDivider = true,
    super.key,
  });

  final AppNotification item;
  final DateTime now;
  final VoidCallback onTap;

  /// pen 마지막 줄 `eu4ww` 는 아래 선을 끈다(#FFFFFF00).
  final bool showDivider;

  // pen 글자 상자: 제목 `u7UpP` 22 · 본문 `mjafy` 21 · 시간 `HiHiY` 17(lineHeight 1.4 · 1.45 · 속성 없음, 렌더 결과).
  // 15px 는 토큰 글자 크기(14 · 16) 사이 값이라 bodySmall 에서 크기만 바꾼다.
  TextStyle get _titleStyle => AppTypography.bodySmall.copyWith(
        fontSize: 15,
        height: 22 / 15,
        fontWeight: item.read ? FontWeight.w400 : FontWeight.w700,
        color: item.read ? AppColors.muted : AppColors.ink,
      );

  TextStyle get _bodyStyle => AppTypography.bodySmall.copyWith(height: 21 / 14, color: AppColors.muted);

  TextStyle get _timeStyle => AppTypography.caption.copyWith(height: 17 / 12, color: AppColors.muted);

  @override
  Widget build(BuildContext context) {
    final time = relativeTimeLabel(item.createdAt, now);
    // 눌림 효과가 스크롤 밖 Material 에 뜨지 않게 줄이 자기 Material 을 갖는다(COMMON §4-2).
    return Semantics(
      button: true,
      onTap: onTap,
      excludeSemantics: true,
      label: '${item.read ? '' : '안 읽은 알림, '}${item.title}, ${item.body}, $time',
      child: Material(
        key: notificationRowKey(item.id),
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: showDivider ? const Border(bottom: BorderSide(color: AppColors.hairlineSoft)) : null,
            ),
            child: Padding(
              // pen padding [14,14]. 아래 선은 높이 안쪽에 그려진다(pen 높이 96 = 14 + 68 + 14).
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _IconCircle(kind: item.kind),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title, style: _titleStyle),
                        const SizedBox(height: 4),
                        Text(item.body, style: _bodyStyle, maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text(time, style: _timeStyle),
                      ],
                    ),
                  ),
                  // pen `z548M` Unread Slot — 읽음 변형은 슬롯을 끈다(점도, 앞의 간격 12 도 없다).
                  if (!item.read) ...[
                    const SizedBox(width: 12),
                    const _UnreadDot(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// pen `Sa6Lv` 44 원(채움 surface-soft) 안에 3D 그림 28(`OaDey`).
class _IconCircle extends StatelessWidget {
  const _IconCircle({required this.kind});

  final NotificationKind kind;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      key: notificationIconCircleKey,
      dimension: 44,
      child: DecoratedBox(
        decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.surfaceSoft),
        child: Center(child: Icon3d(notificationIcon(kind), size: 28)),
      ),
    );
  }
}

/// pen `z548M` 슬롯(폭 8 · 위 여백 7) 안의 `SsMJS` 점 8×8.
class _UnreadDot extends StatelessWidget {
  const _UnreadDot();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 7),
      child: SizedBox.square(
        key: notificationUnreadDotKey,
        dimension: 8,
        child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primary)),
      ),
    );
  }
}
