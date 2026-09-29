import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 화면 15 · 15-5 진입 행(pen 마스터 `fN0xc` "ProfileEntryRow", 쇼케이스 `wmzn0` 안 — Z54et 밖).
/// 받침 원 안 아이콘 → Title/Note → 셰브런. [onTap] 이 있으면 행 전체가 값 수정 화면으로 잇는다(U1 — 화면 15 결정 1
/// "나중에" 의 그 "지금"). [emphasis] 는 15 "친구들이 본 나"(`o9BA0`) 분홍 줄이다.
class ProfileEntryRow extends StatelessWidget {
  const ProfileEntryRow({required this.icon, required this.title, required this.note, this.onTap, this.emphasis = false, super.key});

  final IconData icon;
  final String title;
  final String note;

  /// null 이면 누를 곳이 없다(보이기만 하는 행).
  final VoidCallback? onTap;

  /// 켜면 바탕 primaryWash · 원 흰색 · 아이콘 · 셰브런 primaryText(`o9BA0` override). 크기 · 그림자는 그대로.
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    final radius = BorderRadius.circular(AppRadius.md);
    // pen 높이 84 는 최소값이다 — 글자를 키우면 행이 늘어난다(DESIGN §11.2).
    final content = Container(
      constraints: const BoxConstraints(minHeight: 84),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: _row(),
    );
    // 바탕 #FFFFFF + 카드 그림자 두 겹(pen `fN0xc`, 사용자 결정 09-28). 그림자는 §6 카드 토큰 그대로 Material 밖 상자가
    // 그린다 — Material elevation 은 모양이 토큰과 달라진다. 누르지 않는 행도 같은 모양이다.
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: AppElevation.card),
      // 바탕은 이 Material 이 칠한다 — 안쪽 상자가 또 칠하면 눌림 효과가 그 밑에 깔려 안 보인다. 화면 15 · 15-5 는
      // 스크롤 안이라 눌림 효과를 그릴 Material 을 행 크기로 둔다(COMMON §4-2).
      child: Material(
        color: emphasis ? AppColors.primaryWash : AppColors.canvas,
        borderRadius: radius,
        child: tap == null ? content : InkWell(borderRadius: radius, onTap: tap, child: content),
      ),
    );
  }

  Widget _row() {
    return Row(
      children: [
        // Icon Surface `zdZqS` 44 원 #F7F7F7(흰 바탕 위라 원이 보인다), 아이콘 `GAMlp` 22.
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: emphasis ? AppColors.canvas : AppColors.surfaceSoft, shape: BoxShape.circle),
          child: Icon(icon, size: 22, color: emphasis ? AppColors.primaryText : AppColors.muted),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: _Copy(title: title, note: note)),
        const SizedBox(width: AppSpacing.sm),
        // 셰브런 `vszZo` 20.
        Icon(AppIcons.chevronRight, size: 20, color: emphasis ? AppColors.primaryText : AppColors.muted),
      ],
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
