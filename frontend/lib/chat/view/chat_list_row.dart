import 'package:cached_network_image/cached_network_image.dart';
import 'package:campus_mate/chat/model/conversation.dart';
import 'package:campus_mate/chat/view/chat_time.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 대화 중 한 줄(DESIGN §8.6 `chat-list-row`, pen `L061P2`).
/// 수락 대기 행과 **배경색으로 구분한다** — 누르는 동작이 다른 리스트를 같은 표면에 섞지 않는다.
class ChatListRow extends StatelessWidget {
  const ChatListRow({required this.conversation, required this.onTap, super.key});

  final Conversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = conversation.unreadCount;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 72,
        color: AppColors.canvas,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Row(
          children: [
            _Avatar(url: conversation.partner.avatarUrl),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.partner.nickname,
                    style: AppTypography.bodyStrong.copyWith(color: AppColors.ink),
                  ),
                  Text(
                    // 아직 한 마디도 없는 방. 시스템 줄도 그냥 마지막 메시지라 여기로 들어온다.
                    conversation.lastMessage ?? '아직 메시지가 없어요',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  listTimeLabel(conversation.lastMessageAt, DateTime.now()),
                  style: AppTypography.caption.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: AppSpacing.xxs),
                // 0 이면 뱃지를 그리지 않는다(§8.8 빈 요소 금지).
                if (unread > 0) UnreadBadge(count: unread),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 안 읽은 수 뱃지(pen `Eyh1G`). 세 자리가 되면 화면이 흔들려 "99+" 에서 멈춘다.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: AppTypography.badge.copyWith(color: AppColors.onPrimary),
      ),
    );
  }
}

/// 44dp 원형 아바타. 수락 대기 행과 같은 크기다(pen `grAjV`).
class _Avatar extends StatelessWidget {
  const _Avatar({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.surfaceStrong),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? const Icon(AppIcons.userRound, size: 20, color: AppColors.disabled)
          : CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover),
    );
  }
}
