import 'package:campus_mate/chat/model/chat_repository.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 입력 바(pen `JgryI`). **텍스트만이다** — 사진·파일 버튼을 그리지 않는다(§13-13).
/// 상대가 나간 방에서는 이 위젯 자리가 안내 한 줄로 바뀐다(결정 7) — 여기에 비활성 칸을
/// 남겨 두지 않는다. 눌러도 아무 일 없는 칸이 제일 나쁘다.
class ChatInputBar extends StatefulWidget {
  const ChatInputBar({required this.onSend, required this.isSending, super.key});

  final void Function(String body) onSend;

  /// 보내는 동안 버튼만 잠근다. 낙관적 갱신은 하지 않는다 — 되돌리는 코드가 더 길다.
  final bool isSending;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 공백만 남은 입력은 보낼 수 없다 — 서버도 같은 판단을 한다(422).
  bool get _canSend => !widget.isSending && _controller.text.trim().isNotEmpty;

  void _send() {
    if (!_canSend) {
      return;
    }
    widget.onSend(_controller.text.trim());
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.canvas,
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xs),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44, maxHeight: 120),
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 4,
                  // 1,000자 상한(결정 8). 카운터는 두지 않는다 — 그 길이까지 쓰는 일이 드물다.
                  // **코드포인트로 센다**(백로그 21) — 서버 len()·DB `messages_body_length`(char_length)
                  // 가 그렇게 센다. maxLength·LengthLimitingTextInputFormatter 는 grapheme 으로 세서
                  // 합성 이모지를 넣으면 앱은 통과시키고 서버가 422 로 막는다.
                  inputFormatters: [_codePointLimit],
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _send(),
                  style: AppTypography.body.copyWith(color: AppColors.ink),
                  decoration: InputDecoration(
                    hintText: '메시지를 입력하세요',
                    hintStyle: AppTypography.body.copyWith(color: AppColors.disabled),
                    filled: true,
                    fillColor: AppColors.surfaceSoft,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            _SendButton(onPressed: _canSend ? _send : null),
          ],
        ),
      ),
    );
  }
}

/// 넘치면 앞 [messageMaxLength] 코드포인트만 남긴다.
/// runes 로 자르니 서로게이트 쌍이 반으로 갈리지 않는다(합성 이모지의 ZWJ 사이는 갈릴 수 있다).
final TextInputFormatter _codePointLimit = TextInputFormatter.withFunction((oldValue, newValue) {
  if (newValue.text.runes.length <= messageMaxLength) {
    return newValue;
  }
  // 이미 가득 찬 글에 한 글자 더 넣으면 입력을 무시한다 — 끝 글자를 밀어내지 않고 커서도 제자리다
  // (옛 LengthLimitingTextInputFormatter 와 같은 동작).
  if (oldValue.text.runes.length >= messageMaxLength && oldValue.selection.isCollapsed) {
    return oldValue;
  }
  final text = String.fromCharCodes(newValue.text.runes.take(messageMaxLength));
  // 커서는 입력한 자리에 두되 잘린 글 밖으로는 나가지 않게 한다.
  final offset = newValue.selection.end.clamp(0, text.length);
  return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: offset));
});

/// 원형 40dp 전송 버튼(pen `S64lvQ`).
class _SendButton extends StatelessWidget {
  const _SendButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '보내기',
      // 원을 버튼 자신의 Material 이 칠해야 눌림 효과가 입력 바와 함께 움직인다(COMMON §4-2).
      child: Material(
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        color: onPressed == null ? AppColors.primaryDisabled : AppColors.primary,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              AppIcons.send,
              size: 18,
              color: onPressed == null ? AppColors.disabled : AppColors.onPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
