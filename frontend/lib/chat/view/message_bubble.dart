import 'package:campus_mate/chat/model/message.dart';
import 'package:campus_mate/chat/view/chat_time.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 말풍선 한 개(pen `fm3rk` 상대 / `RvjRp` 나). 시각은 **말풍선 밖 아래**에 둔다(DESIGN §8.6).
/// 시스템 줄은 여기로 오지 않는다 — `SystemMessage` 가 따로 그린다.
class MessageBubble extends StatelessWidget {
  const MessageBubble({required this.message, required this.isMine, super.key});

  final Message message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            // 화면의 78% 를 넘기지 않는다 — 넘기면 누구 말인지 구분이 사라진다.
            constraints:
                BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: isMine ? AppColors.primary : AppColors.surfaceSoft,
                // 꼬리 쪽 모서리 하나만 작게 깎아 방향을 만든다(pen `k7IEF`·`AIqtT`).
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(AppRadius.md),
                  topRight: const Radius.circular(AppRadius.md),
                  bottomLeft: Radius.circular(isMine ? AppRadius.md : 4),
                  bottomRight: Radius.circular(isMine ? 4 : AppRadius.md),
                ),
              ),
              child: Text(
                message.body,
                style: isMine
                    ? AppTypography.body
                        .copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w500)
                    : AppTypography.body.copyWith(color: AppColors.ink),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            timeLabel(message.createdAt),
            style: AppTypography.caption.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
