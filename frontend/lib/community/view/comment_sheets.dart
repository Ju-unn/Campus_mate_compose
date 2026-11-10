import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/community/model/data/poll_comment.dart';
import 'package:campus_mate/community/view/comment_input_bar.dart';
import 'package:campus_mate/community/view/poll_sheets.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/widgets.dart';

enum CommentMenuAction { delete, report }

/// 메뉴에 넣을 동작이 있는 댓글인가 — 내 글에 달린 댓글이면 삭제, 남의 댓글이면 신고. 둘 다 없으면 "…" 를 그리지 않는다.
bool hasCommentMenu(PollComment comment) => comment.canDelete || !comment.isMine;

/// 댓글 "…" 메뉴(pen 18b `tWng7` 삭제 · 18c `ptEjj` 삭제 + 신고 · 18d `Li2Hx` 신고) → 삭제 확인(18e `NF999`) 또는 신고 시트.
/// 시트는 글 메뉴(15d-1 · 15d-2)와 같은 마스터라 `poll_sheets.dart` 의 부품을 그대로 쓴다.
/// 아이콘은 pen 대로 삭제 = lucide trash-2 20 error(글 메뉴 15d-1 과 같다), 신고 = 3D 사이렌 22(Li2Hx 기준).
/// 띄우는 토스트는 [context] 화면 아래, 댓글 입력줄 위([toastBottomInset] = 입력줄의 지금 높이)에 뜬다.
Future<void> showCommentMenu(
  BuildContext context, {
  required PollComment comment,
  required Future<Failure?> Function() onDelete,
  double toastBottomInset = commentInputBarHeight,
}) async {
  final l10n = context.l10n;
  final action = await showPollSheet<CommentMenuAction>(
    context,
    ActionMenuSheet(
      actions: [
        if (comment.canDelete)
          SheetActionRow<CommentMenuAction>(
            // pen 18b · 18c: lucide trash-2 20 error — 글 메뉴(15d-1)와 같다. 신고 줄만 3D 사이렌(Li2Hx).
            icon: const Icon(AppIcons.trash2, size: 20, color: AppColors.error),
            label: l10n.communityDelete,
            value: CommentMenuAction.delete,
            danger: true,
          ),
        if (!comment.isMine)
          SheetActionRow<CommentMenuAction>(
            icon: const Icon3d(AppIcon3d.siren, size: 22),
            label: l10n.commonReport,
            value: CommentMenuAction.report,
          ),
      ],
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case CommentMenuAction.delete:
      await confirmAndDelete(
        context,
        title: context.l10n.communityCommentDeleteConfirmTitle,
        body: context.l10n.communityCommentDeleteConfirmBody,
        delete: onDelete,
        toastBottomInset: toastBottomInset,
      );
    case CommentMenuAction.report:
      await reportComment(context, comment.id, bottomInset: toastBottomInset);
  }
}
