import 'package:campus_mate/community/model/data/community_item.dart';
import 'package:campus_mate/community/view/category_label.dart';
import 'package:campus_mate/community/view/community_card_parts.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 게시물 카드(pen PostCard · Feed `WHqdP` / PostCard · Detail `UCWuL`, 328 폭). 투표 카드와 같은 바깥 모양.
/// 머리줄 48(… 만 — 신고 버튼 없음) → 12 → 카테고리 라벨 → 12 → 본문 16/400 lh1.5 → 12 → 구분선 → 12 → 아래 줄 48(댓글 수만).
/// 피드([detail] false)는 본문 4줄 말줄임 · 카드를 누르면 상세, 상세는 본문 전부 · 카드는 누를 수 없다.
class PostCard extends StatelessWidget {
  const PostCard({required this.item, required this.now, this.detail = false, this.onOpen, this.onMore, super.key});

  final CommunityItem item;
  final DateTime now;
  final bool detail;

  /// 피드에서 상세로 간다. 상세 카드는 null.
  final VoidCallback? onOpen;

  /// … 메뉴. pen 은 게시물 카드에 늘 켜 둔다 — 내 글이면 삭제, 남의 글이면 신고가 든다(부르는 쪽이 정한다).
  final VoidCallback? onMore;

  static const avatarKey = Key('post-card-avatar');
  static const separatorKey = Key('post-card-separator');

  /// 피드 본문 최대 줄(값표 0-3 "앱에서 최대 4줄 말줄임").
  static const int feedMaxLines = 4;

  @override
  Widget build(BuildContext context) {
    final onMore = this.onMore;
    return CommunityCardFrame(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: detail ? null : onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CommunityCardHeader(
            avatarKey: avatarKey,
            createdAt: item.createdAt,
            now: now,
            trailing: onMore == null ? null : CommunityMoreButton(onPressed: onMore),
          ),
          const SizedBox(height: AppSpacing.sm),
          CategoryLabel(category: item.category),
          const SizedBox(height: AppSpacing.sm),
          Text(
            item.text,
            // pen `SiAfB` · `ncnnh` 16/normal lh1.5 ls-0.16 ink.
            style: AppTypography.body.copyWith(height: 1.5, color: AppColors.ink),
            maxLines: detail ? null : feedMaxLines,
            overflow: detail ? null : TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.sm),
          const CommunityCardSeparator(key: separatorKey),
          const SizedBox(height: AppSpacing.sm),
          _Footer(commentCount: item.commentCount),
        ],
      ),
    );
  }
}

/// 아래 줄(pen FooterRow 48): 왼쪽 8 → 말풍선 16 muted → 4 → "댓글 N" 12/500 muted. 투표 카드와 달리 참여 수가 없다.
class _Footer extends StatelessWidget {
  const _Footer({required this.commentCount});

  final int commentCount;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.only(left: AppSpacing.xs),
        child: Row(
          children: [
            const Icon(AppIcons.messageCircle, size: 16, color: AppColors.muted),
            const SizedBox(width: AppSpacing.xxs),
            Flexible(
              child: Text(
                context.l10n.communityCommentCount(count: commentCount),
                style: AppTypography.caption.copyWith(fontWeight: FontWeight.w500, height: 16 / 12, color: AppColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
