import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 안내 한 줄(04-2 설명 줄, 대장 전달 pen 값 10-15): 파란 안내 3D 아이콘 18 → 8 → 14/400 muted.
/// 글이 여러 줄로 접혀도 아이콘은 첫 줄 높이 안 가운데에 선다 — 글 전체 가운데로 내려가지 않는다.
class HintLine extends StatelessWidget {
  const HintLine(this.text, {super.key});

  final String text;

  static const double _iconSize = 18;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.bodySmall.copyWith(color: AppColors.muted);
    // 글자 배율을 따라 첫 줄 높이도 커진다 — 아이콘 자리를 같은 배율로 잡는다.
    final firstLine = MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: firstLine, child: const Center(child: Icon3d(AppIcon3d.infoBlue, size: _iconSize))),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}
