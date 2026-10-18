import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:flutter/material.dart';

/// pen Web/TopBar(보드 UUkLx · A2 PNG): 높이 64, 흰 바탕, 아래 web-hairline 1, 좌우 32.
/// 왼쪽 제목(lg), 오른쪽 관리자 메일 · "2단계 인증됨" 배지 · 로그아웃 글자 단추(사이 16).
class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.title, required this.email, required this.onSignOut});

  final String title;
  final String email;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AdminSizes.topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AdminSpacing.xl),
      color: AdminColors.surface,
      // 선이 높이 64 안의 가운데 정렬을 밀지 않게 앞에 그린다(SideNav 와 같은 이유).
      foregroundDecoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AdminColors.hairline)),
      ),
      child: Row(
        children: [
          Semantics(header: true, child: Text(title, style: AdminTypography.lg.copyWith(color: AdminColors.ink))),
          const Spacer(),
          Text(email, style: AdminTypography.sm.copyWith(color: AdminColors.muted)),
          const SizedBox(width: AdminSpacing.md),
          const StatusBadge('2단계 인증됨'),
          const SizedBox(width: AdminSpacing.md),
          AdminButton(label: '로그아웃', variant: AdminButtonVariant.text, onPressed: onSignOut),
        ],
      ),
    );
  }
}

/// pen Web/StatusBadge 의 초록(성공) 서식: 높이 26 · 좌우 10 · 점 8 + 간격 8 · 글자 12/600 (A2 PNG 측정).
/// 다른 상태색(대기 · 반려 · 정지 …)은 목록 화면 조각에서 더한다.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AdminColors.successWash,
        borderRadius: BorderRadius.circular(AdminRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: AdminSizes.badgeDot,
            height: AdminSizes.badgeDot,
            decoration: const BoxDecoration(color: AdminColors.success, shape: BoxShape.circle),
          ),
          const SizedBox(width: AdminSpacing.xs),
          Text(label, style: AdminTypography.xsStrong.copyWith(color: AdminColors.success)),
        ],
      ),
    );
  }
}
