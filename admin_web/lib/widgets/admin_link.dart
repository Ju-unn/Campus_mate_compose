import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/tap_box.dart';
import 'package:flutter/material.dart';

/// 글자 링크: 14/600 web-primary-text(줄 상자 19 — 통계 카드 높이 146 을 넘기지 않게, 다른 보조 줄과 같다). 통계 카드의 "열기 →" · 표 안의 닉네임(14/600)이 쓴다.
/// 올림 · 누름 · 키보드 초점은 [TapBox] 와 같다. [onTap] 이 없으면 눌리지 않는다.
class AdminLink extends StatelessWidget {
  const AdminLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TapBox(
      onTap: onTap,
      radius: 4,
      cursor: SystemMouseCursors.click,
      child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AdminTypography.smStrong.copyWith(height: AdminTypography.smBox, color: AdminColors.primaryText)),
    );
  }
}
