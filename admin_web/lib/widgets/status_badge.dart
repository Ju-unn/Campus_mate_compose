import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:flutter/material.dart';

/// 배지 색. 다른 상태(반려 · 정지 …)는 그 목록 화면 조각에서 더한다.
enum StatusTone {
  /// "2단계 인증됨"(TopBar IKoKe)
  success(AdminColors.success, AdminColors.successWash),

  /// "대기"(A3 목록 줄)
  warning(AdminColors.warning, AdminColors.warningWash);

  const StatusTone(this.ink, this.wash);

  final Color ink;
  final Color wash;
}

/// pen Web/StatusBadge(DZhY4 · TopBar IKoKe): 높이 26 · 좌우 10 · 점 8 + 6 + 글자 12/700(렌더 16) · 알약 모서리.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key, this.tone = StatusTone.success});

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: tone.wash, borderRadius: BorderRadius.circular(AdminRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            key: const ValueKey('status-badge-dot'),
            width: AdminSizes.badgeDot,
            height: AdminSizes.badgeDot,
            decoration: BoxDecoration(color: tone.ink, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6), // pen DZhY4 gap 6 — 간격 표에 없는 값
          Text(
            label,
            style: AdminTypography.xs.copyWith(fontWeight: FontWeight.w700, height: AdminTypography.xsBox, color: tone.ink),
          ),
        ],
      ),
    );
  }
}
