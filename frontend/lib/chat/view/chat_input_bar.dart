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
                  maxLength: messageMaxLength,
                  buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                      null,
                  inputFormatters: [LengthLimitingTextInputFormatter(messageMaxLength)],
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

/// 원형 40dp 전송 버튼(pen `S64lvQ`).
class _SendButton extends StatelessWidget {
  const _SendButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '보내기',
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: onPressed == null ? AppColors.primaryDisabled : AppColors.primary,
          ),
          child: Icon(
            AppIcons.send,
            size: 18,
            color: onPressed == null ? AppColors.disabled : AppColors.onPrimary,
          ),
        ),
      ),
    );
  }
}
