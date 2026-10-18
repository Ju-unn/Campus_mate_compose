import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 오류 한 줄(pen A1 입력 · A0 실패): 원 느낌표 16 + 간격 6 + 글자 12, 모두 web-danger.
class ErrorRow extends StatelessWidget {
  const ErrorRow(this.message, {super.key, this.lineHeight});

  final String message;

  /// 글자 줄 높이(배수). 비우면 12 글자 토큰의 1.5 — pen 이 렌더 상자 16(= [AdminTypography.xsBox])로 그린 자리에서 쓴다(A5 하트 조정).
  final double? lineHeight;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            // 1.5 배 줄(18)에서는 아이콘을 글자 첫 줄 가운데에 맞추려 1 내린다. 줄 높이를 16 으로 줄인 자리(lineHeight)는 그대로 맞는다.
            padding: EdgeInsets.only(top: lineHeight == null ? 1 : 0),
            child: const Icon(LucideIcons.circleAlert, size: AdminSizes.errorIcon, color: AdminColors.danger),
          ),
          const SizedBox(width: 6), // pen 값(대장 전달 10-18) — 간격 표에 없는 값
          Expanded(child: Text(message, style: AdminTypography.xs.copyWith(height: lineHeight, color: AdminColors.danger))),
        ],
      ),
    );
  }
}
