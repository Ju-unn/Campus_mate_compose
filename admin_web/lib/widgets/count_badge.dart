import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:flutter/material.dart';

/// pen Web/NavBadge(l9ZEF0): 높이 20 · 좌우 6 · 알약 · web-danger 바탕 · 12/700 web-on-primary(글자 상자 16), 폭은 글자에 맞춘다
/// (한 자리는 거의 원). 0 이하는 그리지 않고, 100 이상은 "99+".
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      // 글자 상자 16 + 위아래 2 = 높이 20. alignment 를 주면 부모 폭을 다 채우므로 쓰지 않는다.
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: AdminColors.danger, borderRadius: BorderRadius.circular(AdminRadius.pill)),
      child: Text(
        count >= 100 ? '99+' : '$count',
        maxLines: 1,
        softWrap: false,
        style: AdminTypography.xs.copyWith(fontWeight: FontWeight.w700, height: AdminTypography.xsBox, color: AdminColors.onPrimary),
      ),
    );
  }
}
