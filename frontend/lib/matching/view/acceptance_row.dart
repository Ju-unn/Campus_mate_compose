import 'package:cached_network_image/cached_network_image.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/school_label.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/matching/model/acceptance.dart';
import 'package:flutter/material.dart';

/// 수락 대기 행(DESIGN.md §8.6 `acceptance-row`, pen `XCN1f` → 2026-10-16 `wwfFX`).
/// 버튼을 이름과 한 줄에 두지 않는다 — 학과명이 길면 어긋난다(시안에서 확인된 실제 문제).
/// 결정(거절 · 수락하기)은 행에서 하지 않는다 — "프로필 보기" 로 상대를 본 뒤 그 화면에서 한다(사용자 결정 10-16).
class AcceptanceRow extends StatelessWidget {
  const AcceptanceRow({required this.acceptance, required this.onViewProfile, super.key});

  final Acceptance acceptance;
  final VoidCallback? onViewProfile;

  @override
  Widget build(BuildContext context) {
    final profile = acceptance.profile;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        children: [
          Row(
            children: [
              RowAvatar(url: profile.avatarUrl),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.nameWithAge,
                      style: AppTypography.subtitle.copyWith(color: AppColors.ink),
                    ),
                    SchoolLabel(
                      profile.university ?? '',
                      text: profile.schoolLine,
                      style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // 행 안쪽 폭 전체 × 44(§8.3 카드 안 인라인 버튼 "View Profile").
          AppButton(label: '프로필 보기', onPressed: onViewProfile, height: 44),
        ],
      ),
    );
  }
}

/// 44dp 원형 아바타(§8.6). 아직 아바타가 없는 사람은 회색 원으로 둔다. 받은 신청 · 보낸 신청 행이 같이 쓴다.
class RowAvatar extends StatelessWidget {
  const RowAvatar({required this.url, super.key});

  final String? url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.surfaceStrong),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? const Icon(AppIcons.userRound, size: 20, color: AppColors.disabled)
          : CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover),
    );
  }
}
