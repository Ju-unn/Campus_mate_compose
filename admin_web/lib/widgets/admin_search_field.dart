import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// pen Web/Input · Search(iLB6a · A5 · A8 PNG 측정): 높이 44 · 좌우 12 · web-surface · web-outline 1 · 모서리 8 ·
/// 돋보기 16 web-muted → 10 → 글자 14 web-ink(자리 글자 14 web-muted). 폭은 부모가 정한다(A5 420 · A8 480).
/// [sensitive] 면(학교 메일) 브라우저의 글자 제안 · 자동 고침 · 입력기 학습을 끈다 — 메일이 어디에도 남지 않게.
class AdminSearchField extends StatelessWidget {
  const AdminSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onSubmitted,
    this.enabled = true,
    this.sensitive = false,
    this.maxChars = 254,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onSubmitted;
  final bool enabled;
  final bool sensitive;
  final int maxChars;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(AdminRadius.sm),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    final idle = border(AdminColors.outline);
    return SizedBox(
      height: AdminSizes.control,
      child: TextField(
        controller: controller,
        enabled: enabled,
        onSubmitted: onSubmitted,
        maxLines: 1,
        maxLength: maxChars,
        textInputAction: TextInputAction.search,
        enableSuggestions: !sensitive,
        autocorrect: !sensitive,
        enableIMEPersonalizedLearning: !sensitive,
        textAlignVertical: TextAlignVertical.center,
        style: AdminTypography.sm.copyWith(color: AdminColors.ink),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AdminTypography.sm.copyWith(color: AdminColors.muted),
          counterText: '',
          filled: true,
          fillColor: AdminColors.surface,
          isDense: true,
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: AdminSpacing.sm, right: 10), // 돋보기 → 글자 10 — PNG 측정
            child: Icon(LucideIcons.search, size: 16, color: AdminColors.muted),
          ),
          prefixIconConstraints: const BoxConstraints(),
          contentPadding: const EdgeInsets.fromLTRB(0, AdminSpacing.sm, AdminSpacing.sm, AdminSpacing.sm), // 위아래 12 — 칸이 44 를 채운다(AdminTextField 와 같다)
          enabledBorder: idle,
          disabledBorder: idle,
          focusedBorder: border(AdminColors.primary, 2),
        ),
      ),
    );
  }
}
