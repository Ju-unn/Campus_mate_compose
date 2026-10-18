import 'package:campus_mate_admin/shell/admin_section.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:flutter/material.dart';

/// 메뉴 화면 자리 표시(W0). 내용은 화면마다 다음 조각(W1~W4)에서 채운다.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.section});

  final AdminSection section;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AdminSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text(section.label, style: AdminTypography.lg.copyWith(color: AdminColors.ink))),
          const SizedBox(height: AdminSpacing.xs),
          Text('다음 조각에서 채움', style: AdminTypography.sm.copyWith(color: AdminColors.muted)),
        ],
      ),
    );
  }
}
