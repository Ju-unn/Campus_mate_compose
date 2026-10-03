import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 재화 하트(DESIGN §5.4 — Lucide 가 아니라 이미지). pen `l4vdk` 18.
const String _heartAsset = 'assets/images/heart-flat-vector-v3.png';

/// pen HeartTaskRow `R99dx` — 18a 한 줄. 상태 넷: 미완료 `JQNcz` · 검수중(마스터) · 완료 `gGX34` · 반려 `w3aZL`.
/// 쓴 횟수(1/3) · "이번 주" 는 pen 에 없어 보이지 않는다(대장 09-28).
class HeartTaskRow extends StatelessWidget {
  const HeartTaskRow({required this.task, required this.onTap, super.key});

  final HeartTask task;

  /// 누를 수 있는 줄(미완료 · 반려)만 준다. 검수중 · 완료 줄은 null.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      constraints: const BoxConstraints(minHeight: 64),
      decoration: BoxDecoration(
        border: Border(
          // 반려 줄은 아래 선이 투명하다(pen `w3aZL`).
          bottom: BorderSide(
            color: task.state == HeartTaskState.rejected ? Colors.transparent : AppColors.hairline,
          ),
        ),
      ),
      child: Row(
        children: [
          // pen 3D 28, 줄 안 x0 · 세로 가운데(공지 `k1Fst` · `MLkdv` d7e1q · 공유 n40Hd · 투표 x5QLa, 값표 1004).
          Icon3d(_icon, size: 28),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // pen 14/600, 줄높이 속성 없음 · 렌더 20.
                    Flexible(
                      child: Text(_title, style: AppTypography.labelSmall.copyWith(color: AppColors.ink, height: 20 / 14)),
                    ),
                    if (task.kind == HeartTaskKind.pollVote) ...[const SizedBox(width: 6), const _DailyBadge()],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Image.asset(_heartAsset, width: 18, height: 18, semanticLabel: '하트'),
                    const SizedBox(width: AppSpacing.xxs),
                    Flexible(
                      child: Text(
                        _rewardText,
                        style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _trailing,
        ],
      ),
    );
    final onTap = this.onTap;
    if (onTap == null) return row;
    // 잉크는 줄 자신에 그린다 — 목록을 밀어도 눌림 테두리가 제자리에 뜨지 않게(COMMON §4-2).
    return Material(type: MaterialType.transparency, child: InkWell(onTap: onTap, child: row));
  }

  AppIcon3d get _icon => switch (task.kind) {
        HeartTaskKind.everytimePost => AppIcon3d.megaphone,
        HeartTaskKind.kakaoShare => AppIcon3d.share,
        HeartTaskKind.pollVote => AppIcon3d.vote,
      };

  String get _title => switch (task.kind) {
        HeartTaskKind.everytimePost => '에브리타임 홍보',
        HeartTaskKind.kakaoShare => '학교 단톡방 공유',
        HeartTaskKind.pollVote => '커뮤니티 투표',
      };

  /// "50 · 월 1회" · "10 · 주 최대 30"(pen 글자). 하트 수 · 한도는 서버 값이다.
  String get _rewardText => task.kind == HeartTaskKind.pollVote
      ? '${task.rewardHearts} · 주 최대 ${task.rewardHearts * task.limit}'
      : '${task.rewardHearts} · 월 ${task.limit}회';

  Widget get _trailing => switch (task.state) {
        // 과제는 "인증하기"(대장 09-28, pen 인스턴스 이름 JQNcz), 투표는 pen "참여". #E5E5E5 토큰은 primaryDisabled 하나다.
        HeartTaskState.open => _Chip(
            label: task.kind.needsProof ? '인증하기' : '참여',
            background: AppColors.primaryDisabled,
            foreground: AppColors.ink,
          ),
        // pen `e2aMg` 안 3D 시계 `oq6tX` 16(값표 1004).
        HeartTaskState.reviewing => const _Chip(
            leading: Icon3d(AppIcon3d.clock, size: 16),
            label: '검수중',
            background: AppColors.surfaceStrong,
            foreground: AppColors.muted,
          ),
        HeartTaskState.done => const _Chip(
            leading: Icon(AppIcons.check, size: 12, color: AppColors.primaryText),
            label: '완료',
            background: AppColors.primaryWash,
            foreground: AppColors.primaryText,
          ),
        HeartTaskState.rejected => Text('다시 제출', style: AppTypography.labelSmall.copyWith(color: AppColors.error)),
      };
}

/// pen Status `e2aMg` · Action `xGTbF` — 72×28 알약. 글자를 키우면 늘어난다.
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.background, required this.foreground, this.leading});

  final String label;
  final Color background;
  final Color foreground;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final leading = this.leading;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 72, minHeight: 28),
      child: DecoratedBox(
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppRadius.pill)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (leading != null) ...[leading, const SizedBox(width: AppSpacing.xxs)],
              Text(label, style: AppTypography.badge.copyWith(fontWeight: FontWeight.w700, color: foreground)),
            ],
          ),
        ),
      ),
    );
  }
}

/// pen "매일" 배지 `Aioxz`(투표 줄만).
class _DailyBadge extends StatelessWidget {
  const _DailyBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: AppColors.surfaceStrong, borderRadius: BorderRadius.circular(AppRadius.pill)),
      // pen `klkPA` 글자 칸 16 — badge 토큰 줄높이(1.3)면 14.3 이라 알약이 18.3 으로 얇아진다.
      child: Text(
        '매일',
        style: AppTypography.badge.copyWith(fontWeight: FontWeight.w700, color: AppColors.muted, height: 16 / 11),
      ),
    );
  }
}
