import 'package:cached_network_image/cached_network_image.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/matching/model/acceptance.dart';
import 'package:flutter/material.dart';

/// 수락 대기 행(DESIGN.md §8.6 `acceptance-row`, pen `XCN1f`).
/// 버튼을 이름과 한 줄에 두지 않는다 — 학과명이 길면 어긋난다(시안에서 확인된 실제 문제).
class AcceptanceRow extends StatelessWidget {
  const AcceptanceRow({
    required this.acceptance,
    required this.onReject,
    required this.onAccept,
    super.key,
  });

  final Acceptance acceptance;
  final VoidCallback? onReject;
  final VoidCallback? onAccept;

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
              _Avatar(url: profile.avatarUrl),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.nameWithAge,
                      style: AppTypography.subtitle.copyWith(color: AppColors.ink),
                    ),
                    Text(
                      profile.schoolLine,
                      style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              SizedBox(
                width: 104,
                child: AppButton(
                  label: '거절',
                  onPressed: onReject,
                  variant: AppButtonVariant.secondary,
                  height: 44,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: AppButton(label: '수락하고 대화 시작', onPressed: onAccept, height: 44),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 44dp 원형 아바타(§8.6). 아직 아바타가 없는 사람은 회색 원으로 둔다.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.url});

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
