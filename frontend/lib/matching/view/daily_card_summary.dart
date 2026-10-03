import 'package:cached_network_image/cached_network_image.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/common/widgets/school_label.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/matching/model/daily_card.dart';
import 'package:flutter/material.dart';

/// 요약 카드(DESIGN.md §8.1 `daily-card-summary`, pen `v26S7z`).
/// 카드 전체가 탭 영역이고, 누르면 10b 상세로 이동한다 — 여기에 액션 바는 없다.
class DailyCardSummary extends StatelessWidget {
  const DailyCardSummary({required this.card, required this.onTap, super.key});

  final DailyCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surfaceSoft,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.hairlineSoft),
          boxShadow: AppElevation.cardSoft,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BadgeRow(expiresAt: card.expiresAt),
            const SizedBox(height: AppSpacing.md),
            _SummaryRow(card: card),
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1, color: AppColors.hairlineSoft),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    '프로필 자세히 보기',
                    style: AppTypography.labelSmall.copyWith(color: AppColors.primaryText),
                  ),
                ),
                const Icon(AppIcons.chevronRight, size: 18, color: AppColors.primaryText),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

const weekdayNames = <String>['월', '화', '수', '목', '금', '토', '일'];

/// "오전 7시". 분은 지급 시각이 늘 정시라 뺀다.
String hourLabel(DateTime value) {
  final isMorning = value.hour < 12;
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  return '${isMorning ? '오전' : '오후'} $hour시';
}

/// pen `kaRGO`. "무료 카드 초기화" `ZMHUK`(만료 = 다음 지급 시각) + "학생 인증" `aRL8x`.
/// 구매 카드 배지 `ZvKiJ` 는 조각 7 — 구매 카드는 만료가 없어 시계 배지도 없다.
class _BadgeRow extends StatelessWidget {
  const _BadgeRow({required this.expiresAt});

  final DateTime? expiresAt;

  @override
  Widget build(BuildContext context) {
    final at = expiresAt;
    // 글자를 키워 한 줄에 안 들어가면 다음 줄로 내린다(DESIGN §11.2).
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 6,
      runSpacing: 6,
      children: [
        if (at != null)
          _Pill(
            color: AppColors.primaryDisabled,
            icon: AppIcon3d.clock,
            label: '${weekdayNames[at.weekday - 1]}요일 ${hourLabel(at)}까지',
            textColor: AppColors.ink,
          ),
        const _Pill(color: AppColors.surfaceInk, icon: AppIcon3d.badgeCheck, label: '학생 인증', textColor: AppColors.onInk),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.color, required this.icon, required this.label, required this.textColor});

  final Color color;
  final AppIcon3d icon;
  final String label;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon3d(icon, size: 18),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(child: Text(label, style: AppTypography.badge.copyWith(color: textColor))),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.card});

  final DailyCard card;

  @override
  Widget build(BuildContext context) {
    final profile = card.profile;
    return Row(
      children: [
        _Avatar(url: profile.avatarUrl),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(profile.nameWithAge, style: AppTypography.title.copyWith(color: AppColors.ink)),
              // pen `dmdKV` — 로고는 첫 줄 가운데.
              SchoolLabel(
                profile.university ?? '',
                text: profile.schoolLine,
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 96dp 원형 + 흰 링 3px(§8.1). 아바타가 아직 없는 사람은 회색 원으로 둔다.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceStrong,
        border: Border.all(color: AppColors.canvas, width: 3),
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? const Icon(AppIcons.userRound, color: AppColors.disabled)
          : CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover),
    );
  }
}
