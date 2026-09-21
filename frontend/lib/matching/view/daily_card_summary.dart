import 'package:cached_network_image/cached_network_image.dart';
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
          boxShadow: AppElevation.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _BadgeRow(),
            const SizedBox(height: AppSpacing.sm),
            _SummaryRow(card: card),
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1, color: AppColors.hairlineSoft),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Text(
                  '프로필 자세히 보기',
                  style: AppTypography.label.copyWith(color: AppColors.primaryText),
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

/// pen `kaRGO`. 이번 조각에서 켜지는 배지는 "학생 인증" 하나다 —
/// 구매 카드 배지는 조각 7, "무료 카드 초기화" 배지는 다음 지급 시각을 카드마다 들고 있어야 해서 백로그다.
class _BadgeRow extends StatelessWidget {
  const _BadgeRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surfaceInk,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(AppIcons.badgeCheck, size: 13, color: AppColors.onInk),
              const SizedBox(width: AppSpacing.xxs),
              Text('학생 인증', style: AppTypography.badge.copyWith(color: AppColors.onInk)),
            ],
          ),
        ),
      ],
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
              Text(
                profile.schoolLine,
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
