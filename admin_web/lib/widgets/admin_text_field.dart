import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// pen 사유 · 메모 입력칸(Rj6Ao · A4 대화상자 PNG): 폭 가득 · 안쪽 12 · web-surface · 모서리 8 · 글자 14 web-ink · 자리 글자 14 web-muted.
/// 사유(필수)는 높이 96 · web-outline-strong 1, 메모(선택)는 높이 44 · web-outline 1(PNG 측정). 초점은 코드 칸(A1)과 같은 web-primary 2.
/// 글자는 [AdminTextField.maxLength](500 — 서버 REASON_MAX)를 넘게 들어가지 않는다. 열 때 자동 초점은 두지 않는다 — pen 은
/// 쉬는 테두리로 그렸다(초점 테두리가 열자마자 보이면 시안과 다르다). 키보드는 Tab 한 번에 이 칸으로 온다.
class AdminTextField extends StatelessWidget {
  const AdminTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.multiline = false,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
    this.maxChars = maxLength,
    this.inputFormatters,
    this.keyboardType,
  });

  static const int maxLength = 500;

  final TextEditingController controller;
  final String hint;
  final bool multiline;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  /// 한 줄 칸에서 Enter
  final ValueChanged<String>? onSubmitted;

  /// 넘게 들어가지 않는 글자 수(기본 [maxLength] — 칸마다 서버 상한이 다르면 줄인다)
  final int maxChars;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(AdminRadius.sm),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    final idle = border(multiline ? AdminColors.outlineStrong : AdminColors.outline);
    return SizedBox(
      height: multiline ? 96 : AdminSizes.control,
      child: TextField(
        controller: controller,
        enabled: enabled,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        maxLines: multiline ? null : 1,
        expands: multiline,
        textAlignVertical: multiline ? TextAlignVertical.top : TextAlignVertical.center,
        keyboardType: keyboardType ?? (multiline ? TextInputType.multiline : TextInputType.text),
        inputFormatters: inputFormatters,
        maxLength: maxChars,
        style: AdminTypography.sm.copyWith(color: AdminColors.ink),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AdminTypography.sm.copyWith(color: AdminColors.muted),
          // 글자 수 줄은 pen 에 없다 — 넘는 글자를 막기만 한다
          counterText: '',
          filled: true,
          fillColor: AdminColors.surface,
          isDense: true,
          contentPadding: const EdgeInsets.all(AdminSpacing.sm),
          enabledBorder: idle,
          disabledBorder: idle,
          focusedBorder: border(AdminColors.primary, 2),
        ),
      ),
    );
  }
}
