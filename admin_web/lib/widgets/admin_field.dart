import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/admin_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// pen Web/Input · Field(gAOAp): 라벨 12/600 web-body(렌더 16) → 6 → 입력칸 44(한 줄 · web-outline 1). 칸 모양은 [AdminTextField].
class AdminField extends StatelessWidget {
  const AdminField({
    super.key,
    required this.label,
    required this.controller,
    required this.hint,
    this.enabled = true,
    this.onChanged,
    this.maxChars = AdminTextField.maxLength,
    this.inputFormatters,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final int maxChars;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: AdminTypography.xsStrong.copyWith(height: AdminTypography.xsBox, color: AdminColors.body)),
        const SizedBox(height: 6), // pen gAOAp 라벨 → 칸 — 간격 표에 없는 값
        AdminTextField(
          controller: controller,
          hint: hint,
          enabled: enabled,
          onChanged: onChanged,
          maxChars: maxChars,
          inputFormatters: inputFormatters,
          keyboardType: keyboardType,
        ),
      ],
    );
  }
}
