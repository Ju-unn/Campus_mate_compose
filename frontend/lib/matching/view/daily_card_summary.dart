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
            _BadgeRow(source: card.source, expiresAt: card.expiresAt),
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

/// pen `kaRGO`(화면 `Keynu` 의 `mj74J`). 왼쪽부터 "무료 카드 초기화" `ZMHUK`(만료 = 다음 지급 시각) ·
/// "구매 카드" `ZvKiJ`(구매한 카드만) · "학생 인증" `aRL8x`. 구매 카드는 만료가 없어 시계 배지가 안 뜬다.
///
/// `ZvKiJ` 값(마스터 Badge `XPRBv` 인스턴스, resolveVariables 로 읽음): 채움 #E00B41 = `primary-pressed`,
/// 모서리 999 · 패딩 [6,10] · 간격 4 · 높이 30, 아이콘 lucide `shopping-bag` 18 흰색,
/// 글자 "구매 카드" 11/600 흰색 — `AppTypography.badge` 와 같다(pen lineHeight 1.5 는 기존 배지 둘과 같은 드리프트).
class _BadgeRow extends StatelessWidget {
  const _BadgeRow({required this.source, required this.expiresAt});

  final CardSource source;
  final DateTime? expiresAt;

  @override
  Widget build(BuildContext context) {
    final at = expiresAt;
    // 글자를 키워 한 줄에 안 들어가면 다음 줄로 내린다(DESIGN §11.2).
    // 폭을 꽉 채워야 `alignment: end` 가 먹는다 — 부모 Column 이 start 라 Wrap 이 내용 폭으로 줄어 왼쪽에 붙었다(pen `kaRGO` 는 288 꽉 참, 오른쪽 정렬).
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 6,
        runSpacing: 6,
        children: [
          if (at != null)
            _Pill(
              color: AppColors.primaryDisabled,
              icon: const Icon3d(AppIcon3d.clock, size: 18),
              label: '${weekdayNames[at.weekday - 1]}요일 ${hourLabel(at)}까지',
              textColor: AppColors.ink,
            ),
          if (source == CardSource.purchased)
            const _Pill(
              color: AppColors.primaryPressed,
              icon: Icon(AppIcons.shoppingBag, size: 18, color: AppColors.onPrimary),
              label: '구매 카드',
              textColor: AppColors.onPrimary,
            ),
          const _Pill(
            color: AppColors.surfaceInk,
            icon: Icon3d(AppIcon3d.badgeCheck, size: 18),
            label: '학생 인증',
            textColor: AppColors.onInk,
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.color, required this.icon, required this.label, required this.textColor});

  final Color color;
  final Widget icon;
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
          icon,
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

/// 96dp 원형 + 흰 링 3px(§8.1, pen `JvMzE`: 사진 채움 96 + 안쪽 테두리 3 #FFFFFF).
/// pen 처럼 사진을 96 원 전체로 자르고 링은 그 위에 덧그린다. 링을 `decoration` 의 border 로 두면
/// 사진이 90 정사각으로 안쪽에 밀려 들어가 바깥 96 원으로만 잘리므로 네 변이 평평한 팔각형이 된다.
/// 아바타가 아직 없는 사람은 회색 원으로 둔다.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      foregroundDecoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.canvas, width: 3),
      ),
      child: ClipOval(
        child: ColoredBox(
          color: AppColors.surfaceStrong,
          child: url == null
              ? const Center(child: Icon(AppIcons.userRound, color: AppColors.disabled))
              : CachedNetworkImage(imageUrl: url!, width: 96, height: 96, fit: BoxFit.cover),
        ),
      ),
    );
  }
}
