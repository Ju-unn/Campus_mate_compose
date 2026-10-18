import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/tap_box.dart';
import 'package:flutter/material.dart';

/// pen Web/Chip(꺼짐 xL1CC · 켜짐 wEkG9): 높이 36 · 좌우 14 · 14/600 · 알약 모서리.
/// 꺼짐 web-surface 바탕 + web-outline 1 + web-body 글자, 켜짐 web-ink 바탕 + web-on-primary 글자(테두리 없음).
/// 켜진 칩은 바탕이 web-ink 라 키보드 초점 테두리를 web-on-primary 로 그린다(pen 에 없는 상태).
class AdminChip extends StatelessWidget {
  const AdminChip({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapBox(
      onTap: onTap,
      selected: selected,
      height: AdminSizes.chip,
      radius: AdminRadius.pill,
      color: selected ? AdminColors.ink : AdminColors.surface,
      side: selected ? BorderSide.none : const BorderSide(color: AdminColors.outline),
      focusColor: selected ? AdminColors.onPrimary : AdminColors.ink,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Center(
        widthFactor: 1,
        child: Text(
          label,
          style: AdminTypography.smStrong.copyWith(
            height: AdminTypography.smBox,
            color: selected ? AdminColors.onPrimary : AdminColors.body,
          ),
        ),
      ),
    );
  }
}
