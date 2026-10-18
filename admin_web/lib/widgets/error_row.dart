import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 오류 한 줄(pen A1 입력 · A0 실패): 원 느낌표 16 + 간격 6 + 글자 12, 모두 web-danger.
class ErrorRow extends StatelessWidget {
  const ErrorRow(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(LucideIcons.circleAlert, size: AdminSizes.errorIcon, color: AdminColors.danger),
          ),
          const SizedBox(width: 6), // pen 값(대장 전달 10-18) — 간격 표에 없는 값
          Expanded(child: Text(message, style: AdminTypography.xs.copyWith(color: AdminColors.danger))),
        ],
      ),
    );
  }
}
