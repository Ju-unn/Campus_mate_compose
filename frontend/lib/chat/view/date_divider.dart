import 'package:campus_mate/chat/view/chat_time.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 날짜 구분선(pen `rSFNG`). 날짜가 바뀌는 첫 줄 위에만 들어간다.
class DateDivider extends StatelessWidget {
  const DateDivider({required this.date, super.key});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    const line = Expanded(child: Divider(color: AppColors.hairlineSoft, thickness: 1));
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Text(
            dateLabel(date),
            style: AppTypography.caption.copyWith(color: AppColors.muted),
          ),
        ),
        line,
      ],
    );
  }
}
