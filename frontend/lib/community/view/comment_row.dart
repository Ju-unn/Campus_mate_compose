import 'package:campus_mate/community/model/data/poll_comment.dart';
import 'package:campus_mate/community/view/poll_time.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// "…" 누름 영역(48) 왼쪽에 머리줄 글자가 닿지 않게 비우는 폭.
const double _moreGutter = 36;

/// 댓글 한 줄(pen `CommentRow` f37XJH): 위아래 12 · 세로 간격 4 · 아래 선 1 hairline-soft.
/// 머리줄(24) = 이름 14/600 → "글쓴이" 배지 → 시간 12/500 muted, 오른쪽 끝 "…" 누름 48(이름 줄 위로 12 삐져나온다).
/// 번호는 글 안의 익명 번호다 — 같은 사람은 같은 "익명N". 글쓴이는 번호가 없어(서버 alias_no null) 글 카드와 같은 "익명" 이다.
class CommentRow extends StatelessWidget {
  const CommentRow({required this.comment, required this.now, required this.onMore, super.key});

  final PollComment comment;
  final DateTime now;

  /// 메뉴에 넣을 동작이 하나도 없으면 null — 그때는 "…" 를 그리지 않는다.
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final aliasNo = comment.aliasNo;
    final name = aliasNo == null ? l10n.communityAnonymous : l10n.communityCommentAnonymous(number: aliasNo);
    return DecoratedBox(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.hairlineSoft))),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.xxs,
              children: [
                // 머리줄 높이 24. 글자를 키워 한 줄에 못 들어가면 줄바꿈한다 — 오른쪽 36 은 "…" 누름 영역(48)과 겹치지 않게 비운다.
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 24),
                  child: Padding(
                    padding: const EdgeInsets.only(right: _moreGutter),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.xs,
                        children: [
                          // pen 이름 14/600 줄높이 1.2.
                          Text(name, style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink, height: 1.2)),
                          if (comment.isPostAuthor) const _AuthorBadge(),
                          // pen 시간 12/500 muted, 줄높이 속성 없음 · 렌더 16.
                          Text(
                            relativeTimeLabel(l10n, comment.createdAt, now),
                            style: AppTypography.caption.copyWith(fontWeight: FontWeight.w500, color: AppColors.muted, height: 16 / 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // pen 본문 14 / 줄높이 1.55 / ink.
                Text(comment.body, style: AppTypography.bodySmall.copyWith(color: AppColors.ink)),
              ],
            ),
          ),
          if (onMore != null)
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                tooltip: l10n.commonMore,
                onPressed: onMore,
                constraints: const BoxConstraints.tightFor(width: 48, height: 48),
                icon: const Icon(AppIcons.ellipsis, size: 20, color: AppColors.muted),
              ),
            ),
        ],
      ),
    );
  }
}

/// "글쓴이" 배지(pen Badge · Tint `kJDWN`): primary-wash 알약, 안쪽 [2,8], 글자 12/600 primary-text 줄높이 1.5.
class _AuthorBadge extends StatelessWidget {
  const _AuthorBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: AppColors.primaryWash, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Padding(
        // 세로 2 는 pen 인스턴스 값이라 간격 토큰에 없다.
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
        child: Text(
          context.l10n.communityCommentAuthorBadge,
          style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.primaryText, height: 1.5),
        ),
      ),
    );
  }
}
