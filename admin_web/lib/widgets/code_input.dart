import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 6자리 코드 칸(pen A1 의 칸 6개). 52×60 · 간격 8 · 모서리 8, 테두리 web-outline-strong 1,
/// 지금 칠 칸은 web-primary 2(PNG 측정). 입력은 보이지 않는 글자칸 하나가 받는다 —
/// 붙여넣기 · 인증 앱 자동 채움이 한 번에 들어가고, 칸마다 초점을 옮길 일이 없다(친 만큼 다음 칸이 칠할 칸이 된다).
/// 좁은 창(휴대폰 폭)에서는 칸 줄을 통째로 줄여 넘치지 않게 한다 — 1280 이상에선 늘 원래 크기다.
class CodeInput extends StatelessWidget {
  const CodeInput({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    this.onChanged,
  });

  static const int length = 6;

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmitted;

  /// 글자가 바뀔 때마다(붙여넣기 포함)
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: length * AdminSizes.codeCellWidth + (length - 1) * AdminSpacing.xs,
        height: AdminSizes.codeCellHeight,
        child: Stack(
          children: [
            ListenableBuilder(listenable: Listenable.merge([controller, focusNode]), builder: (_, _) => _cells()),
            Positioned.fill(child: Opacity(opacity: 0, child: _field())),
          ],
        ),
      ),
    );
  }

  Widget _cells() {
    final text = controller.text;
    final active = focusNode.hasFocus ? text.length.clamp(0, length - 1) : -1;
    return Row(
      children: [
        for (var i = 0; i < length; i++) ...[
          if (i > 0) const SizedBox(width: AdminSpacing.xs),
          _Cell(key: ValueKey('code-cell-$i'), digit: i < text.length ? text[i] : '', active: i == active),
        ],
      ],
    );
  }

  Widget _field() {
    return Semantics(
      label: '6자리 인증 코드',
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: true,
        showCursor: false,
        // 선택을 막지 않는다 — 막으면 Ctrl+V 붙여넣기(1Password 등에서 복사한 코드)까지 막힐 수 있다.
        keyboardType: TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode],
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(length),
        ],
        onChanged: onChanged,
        onSubmitted: (_) => onSubmitted(),
        decoration: const InputDecoration.collapsed(hintText: null),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({super.key, required this.digit, required this.active});

  final String digit;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AdminSizes.codeCellWidth,
      height: AdminSizes.codeCellHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(AdminRadius.sm),
        border: active
            ? Border.all(color: AdminColors.primary, width: 2)
            : Border.all(color: AdminColors.outlineStrong),
      ),
      child: Text(digit, style: AdminTypography.lg.copyWith(color: AdminColors.ink)),
    );
  }
}
