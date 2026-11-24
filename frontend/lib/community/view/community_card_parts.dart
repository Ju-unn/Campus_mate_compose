import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/community/view/poll_time.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 피드 카드 둘(투표 `ffFIS` · 게시물 `WHqdP`)과 게시물 상세(`UCWuL`)가 같이 쓰는 조각.

/// 바깥 틀: 흰 · 모서리 lg(24) · 그림자 (0,1) 8 #00000014(`AppElevation.homeTileLow`).
/// 색 · 그림자는 바깥 DecoratedBox, 눌림 효과는 안쪽 투명 Material 이 받는다(COMMON §4-2).
class CommunityCardFrame extends StatelessWidget {
  const CommunityCardFrame({required this.padding, required this.child, this.onTap, super.key});

  final EdgeInsets padding;
  final Widget child;

  /// 카드 아무 데나 누르면(게시물 피드 카드 → 상세). 없으면 카드 자체는 누를 수 없다.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg));
    final content = Padding(padding: padding, child: child);
    return DecoratedBox(
      decoration: ShapeDecoration(color: AppColors.canvas, shape: shape, shadows: AppElevation.homeTileLow),
      child: Material(
        type: MaterialType.transparency,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

/// 머리줄(pen `bNiFM` · `edIA2`, 296×48 · 간격 10 · 세로 가운데): 익명 아바타 40(원 primary-wash + 3D 프로필 24) →
/// "익명" 14/600 ink · 시간 12/500 muted(둘 다 줄높이 속성 없음, 렌더 19 · 16) → 빈칸 → [trailing](신고 · … 48).
class CommunityCardHeader extends StatelessWidget {
  const CommunityCardHeader({required this.createdAt, required this.now, this.trailing, this.avatarKey, super.key});

  final DateTime createdAt;
  final DateTime now;
  final Widget? trailing;

  /// 시험이 아바타 자리 · 크기를 잰다.
  final Key? avatarKey;

  /// pen 머리줄 간격 10 — 간격 토큰 xs(8) · sm(12) 사이 값이라 토큰으로 갈음하지 않는다.
  static const double gap = 10;

  /// 신고 · … 누름 영역이 48 이라 머리줄이 48. 오른쪽 버튼이 없어도 높이는 같다.
  static const double height = 48;

  @override
  Widget build(BuildContext context) {
    final trailing = this.trailing;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: height),
      child: Row(
        children: [
          Container(
            key: avatarKey,
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.primaryWash, shape: BoxShape.circle),
            child: const Icon3d(AppIcon3d.userRound, size: 24),
          ),
          const SizedBox(width: gap),
          Expanded(
            child: Column(
              // 높이가 정해진 자리에 놓여도 두 줄 높이만 쓴다 — 머리줄이 늘어나지 않게.
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.communityAnonymous, style: AppTypography.labelSmall.copyWith(height: 19 / 14, color: AppColors.ink)),
                Text(
                  relativeTimeLabel(context.l10n, createdAt, now),
                  style: AppTypography.caption.copyWith(fontWeight: FontWeight.w500, height: 16 / 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: gap), trailing],
        ],
      ),
    );
  }
}

/// … 버튼(pen MoreButton `B8pl1` 덮어쓰기: 누름 48 · ellipsis 20 muted).
class CommunityMoreButton extends StatelessWidget {
  const CommunityMoreButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.l10n.commonMore,
      icon: const Icon(AppIcons.ellipsis, size: 20, color: AppColors.muted),
      onPressed: onPressed,
    );
  }
}

/// 카드 아래 줄 위 구분선(pen Separator `CqBWB` 1 #EBEBEB).
class CommunityCardSeparator extends StatelessWidget {
  const CommunityCardSeparator({super.key});

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: AppColors.hairlineSoft, child: SizedBox(height: 1, width: double.infinity));
}
