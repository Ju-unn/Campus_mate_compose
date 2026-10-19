import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:flutter/material.dart';

/// 배지 색(pen ⑤ DZhY4). 다른 상태는 그 목록 화면 조각에서 더한다.
enum StatusTone {
  /// "2단계 인증됨"(TopBar IKoKe) · 신고 "조치" · 글 "보임"
  success(AdminColors.success, AdminColors.successWash),

  /// "대기"(A3 목록 줄 · A4 열린 신고)
  warning(AdminColors.warning, AdminColors.warningWash),

  /// 신고 "기각"
  neutral(AdminColors.muted, AdminColors.surfaceStrong),

  /// "정지" · 글 "가려짐"
  danger(AdminColors.danger, AdminColors.dangerWash),

  /// 사용자 상세 머리의 "카카오 로그인"(pen A5 — 점 · 글자 web-ink, 바탕 web-surface-strong)
  plain(AdminColors.ink, AdminColors.surfaceStrong),

  /// 매칭 "대화 중"(pen A9 — 바탕 web-primary-wash · 점 · 글자 web-primary-text)
  primary(AdminColors.primaryText, AdminColors.primaryWash);

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
