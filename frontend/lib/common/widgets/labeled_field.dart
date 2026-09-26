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
    this.guideText,
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

  /// 쓰는 도중 조건에 못 미칠 때의 안내(예: 06-2a "10자 이상"). 오류 줄과 같은 자리에 아이콘 없이 회색으로 그린다
  /// — 아직 잘못이 아니라서 표식을 빼고, 눌러서 오류가 되면 같은 자리에서 빨간 줄로 바뀐다(pen vMxds·fGKgO).
  final String? guideText;
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
            // 오류 때는 테두리도 빨간 2px 다(pen 마스터 PccKZ) — 문구만 빨개서는 어느 칸 얘기인지 흐리다.
            border: _border(AppColors.outline),
            enabledBorder: errorText != null ? _errorBorder : _border(AppColors.outline),
            focusedBorder: errorText != null ? _errorBorder : _border(AppColors.primary),
          ),
        ),
        if (errorText != null)
          _note(const Icon(AppIcons.circleAlert, size: 14, color: AppColors.error), AppColors.error, errorText!)
        else if (pendingText != null)
          _note(_spinner, AppColors.muted, pendingText!)
        else if (successText != null)
          _note(const Icon(AppIcons.circleCheck, size: 14, color: AppColors.success), AppColors.success, successText!)
        else if (guideText != null)
          _note(null, AppColors.muted, guideText!)
        // 도움말은 칸에 바로 붙는다(간격 0, pen 04-1 MLJum·EKXNe).
        else if (helper != null)
          Text(helper!, style: AppTypography.caption.copyWith(color: AppColors.muted)),
      ],
    );
  }

  static const Widget _spinner = SizedBox(
    width: 14,
    height: 14,
    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.muted),
  );

  /// 입력칸 바로 아래 한 줄(표식 + 문구). 오류·확인 중·사용 가능은 색만으로 전달하지 않도록 표식을 같이 둔다.
  /// 칸과의 간격 8 은 pen 확인 줄 a1eaV 값이다. 확인 중 표식은 pen 의 정지 아이콘(loader-circle) 대신
  /// 도는 원을 그대로 둔다(DESIGN §8.5 "도는 표시"). 표식이 없는 줄(쓰는 도중 안내)은 글자가 칸 왼쪽 끝에서 시작한다.
  Widget _note(Widget? leading, Color color, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          if (leading != null) ...[leading, const SizedBox(width: AppSpacing.xxs)],
          Expanded(child: Text(text, style: AppTypography.caption.copyWith(color: color))),
        ],
      ),
    );
  }

  static final OutlineInputBorder _errorBorder = _border(AppColors.error, width: 2);

  static OutlineInputBorder _border(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
