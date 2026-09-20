import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 라벨이 붙은 입력칸(datingApp.pen `TextInput`).
/// 라벨 - 입력칸 - 도움말 순서로 쌓고, 오류가 있으면 도움말 대신 오류를 보여준다.
class LabeledField extends StatelessWidget {
  const LabeledField({
    required this.label,
    this.initialValue,
    this.controller,
    this.onChanged,
    this.placeholder,
    this.helper,
    this.errorText,
    this.keyboardType,
    this.inputFormatters,
    this.maxLines = 1,
    super.key,
  });

  final String label;
  final String? initialValue;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String? placeholder;
  final String? helper;
  final String? errorText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.labelSmall.copyWith(color: AppColors.body)),
        const SizedBox(height: AppSpacing.xs),
        TextFormField(
          initialValue: controller == null ? initialValue : null,
          controller: controller,
          onChanged: onChanged,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          maxLines: maxLines,
          style: AppTypography.body.copyWith(color: AppColors.ink),
          decoration: InputDecoration(
            hintText: placeholder,
            hintStyle: AppTypography.body.copyWith(color: AppColors.disabled),
            filled: true,
            fillColor: AppColors.surfaceSoft,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            border: _border(AppColors.outline),
            enabledBorder: _border(AppColors.outline),
            focusedBorder: _border(AppColors.primary),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Row(
            children: [
              const Icon(AppIcons.circleAlert, size: 14, color: AppColors.error),
              const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: Text(errorText!, style: AppTypography.caption.copyWith(color: AppColors.error)),
              ),
            ],
          ),
        ] else if (helper != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(helper!, style: AppTypography.caption.copyWith(color: AppColors.muted)),
        ],
      ],
    );
  }

  OutlineInputBorder _border(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: BorderSide(color: color),
    );
  }
}
