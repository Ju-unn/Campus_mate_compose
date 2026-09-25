import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 라벨이 붙은 입력칸(datingApp.pen `TextInput`).
/// 라벨 - 입력칸 - 도움말 순서로 쌓고, 입력칸 아래 한 줄은 오류 > 성공 > 도움말 순으로 하나만 보여준다.
class LabeledField extends StatelessWidget {
  const LabeledField({
    required this.label,
    this.initialValue,
    this.controller,
    this.onChanged,
    this.placeholder,
    this.helper,
    this.errorText,
    this.successText,
    this.pendingText,
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

  /// 통과했다는 안내(예: 닉네임 중복확인). 색만으로 전달하지 않도록 체크 아이콘을 같이 그린다(DESIGN §8.5).
  final String? successText;

  /// 서버 답을 기다리는 동안의 안내. 회색 + 도는 표시를 같이 그린다(DESIGN §8.5).
  final String? pendingText;
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
        if (errorText != null)
          _note(const Icon(AppIcons.circleAlert, size: 14, color: AppColors.error), AppColors.error, errorText!)
        else if (pendingText != null)
          _note(_spinner, AppColors.muted, pendingText!)
        else if (successText != null)
          _note(const Icon(AppIcons.check, size: 14, color: AppColors.success), AppColors.success, successText!)
        else if (helper != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(helper!, style: AppTypography.caption.copyWith(color: AppColors.muted)),
        ],
      ],
    );
  }

  static const Widget _spinner = SizedBox(
    width: 14,
    height: 14,
    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.muted),
  );

  /// 입력칸 바로 아래 한 줄(표식 + 문구). 색만으로 전달하지 않도록 표식을 항상 같이 둔다.
  Widget _note(Widget leading, Color color, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxs),
      child: Row(
        children: [
          leading,
          const SizedBox(width: AppSpacing.xxs),
          Expanded(child: Text(text, style: AppTypography.caption.copyWith(color: color))),
        ],
      ),
    );
  }

  OutlineInputBorder _border(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: BorderSide(color: color),
    );
  }
}
