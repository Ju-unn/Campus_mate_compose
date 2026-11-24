import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 입력칸 바로 아래 오류 줄(datingApp.pen TextInput `PccKZ` ErrorRow): 위 8 · circleAlert 14 · 4 · 12 error.
/// 색만으로 전달하지 않도록 표식을 같이 둔다. [LabeledField] 의 오류 줄과 02 학교 메일 칸(pen V1uDE4)이 같이 쓴다.
class FieldErrorLine extends StatelessWidget {
  const FieldErrorLine(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          const Icon(AppIcons.circleAlert, size: 14, color: AppColors.error),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(child: Text(text, style: AppTypography.caption.copyWith(color: AppColors.error))),
        ],
      ),
    );
  }
}
