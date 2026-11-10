import 'package:campus_mate/chat/view/chat_input_bar.dart';
import 'package:campus_mate/community/model/data/poll_comment.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 보내기 누름 영역. 테스트가 크기(44 이상)를 재는 데 쓴다.
const Key commentSendButtonKey = ValueKey('comment-send-button');

/// 댓글 입력줄 높이(pen `JgryI` 80 = 위 12 + 칸 48 + 아래 20). 토스트가 이 줄을 가리지 않게 올리는 데 쓴다.
const double commentInputBarHeight = 80;

/// 댓글 입력 바(pen `JgryI` · 칸 `dT2J7` 280×48 radius 22 · 보내기 `S64lvQ`). 채팅 입력 바와 비슷하지만 따로 둔다 —
/// 200자 상한 · 안내 글 · 보내기 누름 영역(원은 40 이지만 누르는 영역은 48, 접근성 44 이상)이 다르다.
class CommentInputBar extends StatefulWidget {
  const CommentInputBar({required this.onSend, required this.isSending, super.key});

  /// 보냈으면 true. false 면 비웠던 글을 칸에 되돌린다 — 한도 · 연결 실패로 막혀도 다시 쓰지 않게.
  final Future<bool> Function(String body) onSend;

  /// 보내는 동안 버튼만 잠근다.
  final bool isSending;

  @override
  State<CommentInputBar> createState() => _CommentInputBarState();
}

class _CommentInputBarState extends State<CommentInputBar> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 공백만 남은 입력은 보낼 수 없다 — 서버도 같은 판단을 한다(422).
  bool get _canSend => !widget.isSending && _controller.text.trim().isNotEmpty;

  Future<void> _send() async {
    if (!_canSend) return;
    final body = _controller.text.trim();
    _controller.clear();
    // 보내는 동안 새로 쓴 글이 있으면 덮지 않는다.
    if (!await widget.onSend(body) && mounted && _controller.text.isEmpty) {
      setState(() => _controller.value = TextEditingValue(text: body, selection: TextSelection.collapsed(offset: body.length)));
    }
  }

  @override
  Widget build(BuildContext context) {
    // pen 흰 바탕 · 위쪽 선만 #DDDDDD 1, 안쪽 [12,16,20,16]. 오른쪽만 12 — 보내기 누름 영역 48 이 원(40)보다 4 넓어서
    // 원은 pen 자리(x 304 ~ 344)에 그대로 있고 칸은 280 이다. 선은 여백을 먹지 않게 위에 덧그린다.
    return Container(
      color: AppColors.canvas,
      foregroundDecoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.hairline))),
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.sm, 20),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 4,
                  inputFormatters: [_commentLimit],
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _send(),
                  style: AppTypography.body.copyWith(color: AppColors.ink),
                  textAlignVertical: TextAlignVertical.center,
                  decoration: InputDecoration(
                    hintText: context.l10n.communityCommentInputHint,
                    hintStyle: AppTypography.body.copyWith(color: AppColors.muted),
                    hintMaxLines: 1,
                    filled: true,
                    fillColor: AppColors.surfaceSoft,
                    contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xxs),
            _SendButton(onPressed: _canSend ? _send : null),
          ],
        ),
      ),
    );
  }
}

/// 댓글 입력 상한(200자). 코드 포인트로 센다 — 서버 len() · DB char_length 와 같다(채팅 입력 바와 같은 이유).
final TextInputFormatter _commentLimit = codePointLimitFormatter(commentMaxLength);

/// 보이는 원 40(pen `S64lvQ`), 누르는 영역 48.
class _SendButton extends StatelessWidget {
  const _SendButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    // 꺼진 버튼도 탭을 삼킨다 — 안 그러면 탭이 앱 전체를 감싼 KeyboardDismissOnTap 으로 넘어가 쓰던 키보드가 내려간다.
    return GestureDetector(
      onTap: enabled ? null : () {},
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: context.l10n.chatSend,
        // 눌림 효과는 버튼 자신의 Material 이 그려 입력 바와 함께 움직인다(COMMON §4-2).
        child: SizedBox.square(
          key: commentSendButtonKey,
          dimension: 48,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(shape: BoxShape.circle, color: enabled ? AppColors.primary : AppColors.primaryDisabled),
                  child: SizedBox.square(
                    dimension: 40,
                    child: Icon(AppIcons.send, size: 18, color: enabled ? AppColors.onPrimary : AppColors.disabled),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
