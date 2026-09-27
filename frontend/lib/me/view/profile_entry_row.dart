import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 화면 15 진입 행(pen 마스터 `fN0xc` "ProfileEntryRow", 쇼케이스 `wmzn0` 안 — Z54et 밖).
/// 받침 원 안 아이콘 → Title/Note → 셰브런. 셰브런은 pen 대로 보이지만 누를 곳은 아직 없다 —
/// 값 수정 화면을 만들 때 단다(사용자 결정 2026-09-27). 강조 variant(친구들이 본 나)는 이번에 쓰지 않는다.
class ProfileEntryRow extends StatelessWidget {
  const ProfileEntryRow({required this.icon, required this.title, required this.note, super.key});

  final IconData icon;
  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    // pen 높이 84 는 최소값이다 — 글자를 키우면 행이 늘어난다(DESIGN §11.2).
    return Container(
      constraints: const BoxConstraints(minHeight: 84),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          // Icon Surface `zdZqS` 44 원, 아이콘 `GAMlp` 22.
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(color: AppColors.canvas, shape: BoxShape.circle),
            child: Icon(icon, size: 22, color: AppColors.muted),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _Copy(title: title, note: note)),
          const SizedBox(width: AppSpacing.sm),
          // 셰브런 `vszZo` 20.
          const Icon(AppIcons.chevronRight, size: 20, color: AppColors.muted),
        ],
      ),
    );
  }
}

/// Copy `iksDh` — Title `ZMu82` 16/600, gap 3(토큰 밖 리터럴), Note `B4ppA` 14/400.
class _Copy extends StatelessWidget {
  const _Copy({required this.title, required this.note});

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Column(
      // max 면 행 안에서 세로를 다 먹어 행이 부모 높이만큼 커진다.
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // pen 줄높이 1.5 인데 렌더 높이는 25(`ZMu82`) — 25/16 으로 맞춘다. subtitle 토큰(17/600)이 아니라 16/600 이 pen 값이다.
        Text(title, style: AppTypography.bodyStrong.copyWith(height: 25 / 16, color: AppColors.ink)),
        const SizedBox(height: 3),
        Text(note, style: AppTypography.bodySmall.copyWith(height: 1.5, color: AppColors.muted)),
      ],
    );
  }
}
