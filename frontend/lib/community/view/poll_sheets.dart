import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/widgets/delete_confirm_sheet.dart';
import 'package:campus_mate/common/widgets/sheet_handle.dart';
import 'package:campus_mate/community/view/poll_toast.dart';
import 'package:campus_mate/community/viewmodel/community_feed_view_model.dart';
import 'package:campus_mate/core/l10n/error_text.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/safety/model/data/report_target.dart';
import 'package:campus_mate/safety/view/report_sheet.dart';
import 'package:campus_mate/safety/view/safety_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 메뉴 시트는 채팅탭 `ChatRoomMenuSheet`(Menu · Chat `RzZT8`) · 차단 확인과 같은 마스터다(결정 D4).

/// 남의 글 신고(A16 · 신고 버튼 `uPUf3`). 받은 리뷰 신고(20c)와 같은 흐름 — 글쓴이는 익명이라 차단할 상대가 없어
/// `reportThenLeave` 를 쓰지 않고, 어느 결과든 카드는 그대로 남는다(가림은 운영자가 한다, 서버 #191).
/// 띄운 토스트를 돌려준다(시트를 그냥 닫으면 null).
/// [bottomInset] 은 화면 아래에 붙은 줄(17c 댓글 입력줄)의 높이 — 토스트가 그 줄을 가리지 않게 올린다.
Future<PollToast?> reportPoll(BuildContext context, String pollId, {double bottomInset = 0}) =>
    _report(context, ReportTarget.poll(pollId), bottomInset);

/// 남의 댓글 신고(17c 댓글 "…" 메뉴 → 신고하기). 글 신고와 같은 시트 · 같은 토스트 — 댓글은 남고 가림은 운영자가 한다.
Future<PollToast?> reportComment(BuildContext context, String commentId, {double bottomInset = 0}) =>
    _report(context, ReportTarget.pollComment(commentId), bottomInset);

Future<PollToast?> _report(BuildContext context, ReportTarget target, double bottomInset) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n; // 시트가 닫힌 뒤 화면이 없어져도 토스트는 띄운다 — 글자를 만들 도구는 미리 잡는다.
  final result = await showReportSheet(context, target);
  if (result == null) return null;
  final failure = result.failure;
  return showSafetyToast(
    messenger,
    failure == null ? l10n.commonReportedNotice : failureText(l10n, failure),
    bottomInset: bottomInset,
  );
}

/// 내 글 "…"(15d-1 `RCNu0`) → "삭제하기" → 확인(15d-2 `K64Q8p`) → 지우기(사용자 결정 2).
/// 지우는 동안 확인 시트는 열린 채 "삭제하기" 만 꺼지고(15d-2 삭제 중 `EIEFb`), 끝나면 닫고 "삭제했어요"(15d-5 `SKQgV`)
/// 또는 오류 토스트. 도중에 시트를 닫아도 요청이 끝나면 결과를 알린다 — 서버에서는 이미 지워졌을 수 있다.
/// 띄운 토스트를 돌려준다(지우지 않았으면 null).
Future<PollToast?> showPollMenu(BuildContext context, WidgetRef ref, String pollId) async {
  final wantsDelete = await showPollSheet<bool>(
    context,
    ActionMenuSheet(
      actions: [
        SheetActionRow<bool>(
          icon: const Icon(AppIcons.trash2, size: 20, color: AppColors.error),
          label: context.l10n.communityDelete,
          value: true,
          danger: true,
        ),
      ],
    ),
  );
  if (wantsDelete != true || !context.mounted) return null;
  return confirmAndDelete(
    context,
    title: context.l10n.communityDeleteConfirmTitle,
    body: context.l10n.communityDeleteConfirmBody,
    delete: () => ref.read(communityFeedViewModelProvider.notifier).delete(pollId),
  );
}

/// 확인 시트 → 지우기 → 결과 토스트. 지우는 동안 확인 시트는 열린 채 "삭제하기" 만 꺼지고, 끝나면 닫고 "삭제했어요" 또는 오류 토스트.
/// 도중에 시트를 닫아도 요청이 끝나면 결과를 알린다. 지우지 않았으면(취소) null. 글 삭제(15d-2)와 댓글 삭제(18e)가 같이 쓴다.
Future<PollToast?> confirmAndDelete(
  BuildContext context, {
  required String title,
  required String body,
  required Future<Failure?> Function() delete,
  double toastBottomInset = 0,
}) async {
  Future<Failure?>? deleting;
  await showPollSheet<void>(
    context,
    DeleteConfirmSheet(
      title: title,
      body: body,
      confirmLabel: context.l10n.communityDelete,
      onDelete: () async {
        await (deleting = delete());
      },
    ),
  );
  if (deleting == null) return null; // "삭제하기" 를 누르지 않고 닫았다.
  final failure = await deleting;
  if (!context.mounted) return null;
  final l10n = context.l10n;
  return showPollToast(
    context,
    failure == null ? l10n.communityDeleted : failureText(l10n, failure),
    bottomInset: toastBottomInset,
  );
}

Future<T?> showPollSheet<T>(BuildContext context, Widget sheet) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // 기본 딤(0.8)은 시안보다 어둡다 — 모달 딤 토큰(0.5)을 쓴다(채팅 시트와 같다).
    barrierColor: AppColors.scrim,
    builder: (_) => sheet,
  );
}

/// 누르는 행. ListTile 은 쓰지 않는다 — 가장 가까운 Material 이 시트 밖이면 눌림 효과가 떠 있다(COMMON §4-2).
class SheetRow extends StatelessWidget {
  const SheetRow({required this.onTap, required this.child, super.key});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 52), child: child),
      ),
    );
  }
}

/// 메뉴 시트(Menu · Chat `RzZT8` 계열 — 15d-1 `ofjwb` · 댓글 18b ~ 18d): #FFF · 위 radius 24 · 안쪽 [12,16,24,16] · 간격 4,
/// 손잡이 36×4 → 행들(각 52, 안쪽 [0,4], 아이콘 + 12 + 16/400) → 구분선 1 hairlineSoft → "취소" 16/600.
class ActionMenuSheet extends StatelessWidget {
  const ActionMenuSheet({required this.actions, super.key});

  /// [SheetActionRow] 들. 누르면 그 값을 들고 시트가 닫힌다.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: SafeArea(
        top: false,
        // 글자를 키운 기기에서 시트가 화면보다 길어지면 스크롤한다.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.xxs,
            children: [
              const Center(child: SheetHandle()),
              ...actions,
              const ColoredBox(color: AppColors.hairlineSoft, child: SizedBox(height: 1)),
              SheetRow(
                onTap: () => Navigator.of(context).pop(),
                child: Center(
                  child: Text(
                    context.l10n.commonCancel,
                    style: AppTypography.bodyStrong.copyWith(color: AppColors.ink, height: 23 / 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 메뉴 시트의 행 하나: [icon] + 12 + 글자 16/400. 누르면 [value] 를 들고 닫힌다. [danger] 면 error 색 글자(삭제하기).
class SheetActionRow<T> extends StatelessWidget {
  const SheetActionRow({required this.icon, required this.label, required this.value, this.danger = false, super.key});

  final Widget icon;
  final String label;
  final T value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return SheetRow(
      onTap: () => Navigator.of(context).pop(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        child: Row(
          children: [
            icon,
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                // pen 16 / normal, 줄높이 속성 없음 · 렌더 23(채팅 메뉴 행과 같다).
                style: AppTypography.body.copyWith(color: danger ? AppColors.error : AppColors.ink, height: 23 / 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
