import 'package:campus_mate_admin/heart_tasks/heart_task_item.dart' show formatSubmittedAt;
import 'package:campus_mate_admin/notices/notice_controller.dart';
import 'package:campus_mate_admin/notices/notice_dialog.dart';
import 'package:campus_mate_admin/notices/notice_item.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:campus_mate_admin/reports/report_controller.dart' show ActionResult;
import 'package:campus_mate_admin/reports/report_dialogs.dart';
import 'package:campus_mate_admin/reports/report_item.dart' show missingValue;
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_dialog.dart';
import 'package:campus_mate_admin/widgets/admin_table.dart';
import 'package:campus_mate_admin/widgets/admin_toast.dart';
import 'package:campus_mate_admin/widgets/error_row.dart';
import 'package:campus_mate_admin/widgets/load_states.dart';
import 'package:campus_mate_admin/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 공지사항(`/notices`, 할 일 21). pen 에 화면이 없어 문의 목록(신고 목록 A4 틀)을 따른다: 내용 32 안쪽, 머리 줄([공지 쓰기] 오른쪽) → 24 →
/// 표(머리 44 · 줄 52 — 올린 시각 160 · 제목 220 · 내용 260 · 상태 120(가려짐 배지) · 그림 80 · [지우기] 남는 폭) → [더 보기] → 안내.
/// 가린 공지도 보인다(상태 배지). 가림 · 해제는 이 화면에 없다 — 신고 상세의 글 가림 길(polls)이다.
class NoticeScreen extends ConsumerWidget {
  const NoticeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(noticeListProvider);
    final controller = ref.read(noticeListProvider.notifier);
    final Widget body;
    if (list.loading) {
      body = const LoadingBlock('공지를 불러오고 있어요');
    } else if (list.failed) {
      body = ErrorBlock('공지를 불러오지 못했어요', onRetry: controller.reload);
    } else if (list.items.isEmpty) {
      body = const EmptyBlock('올린 공지가 없어요');
    } else {
      body = _Rows(list: list, onMore: controller.loadMore, onDelete: (item) => _delete(context, controller, item));
    }
    return Padding(
      padding: const EdgeInsets.all(AdminSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: AdminButton(label: '공지 쓰기', onPressed: () => _create(context, ref, controller)),
          ),
          const SizedBox(height: AdminSpacing.lg),
          Expanded(child: SingleChildScrollView(child: body)),
        ],
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref, NoticeListController controller) async {
    final done = await showAdminDialog<bool>(
      context,
      (_) => NoticeCreateDialog(
        onPick: ref.read(imagePickerProvider),
        onSubmit: (title, body, image) => controller.create(title: title, body: body, image: image),
      ),
    );
    if (done == true && context.mounted) AdminToast.show(context, '공지를 올렸어요');
  }

  Future<void> _delete(BuildContext context, NoticeListController controller, NoticeItem item) async {
    final outcome = await showAdminDialog<DialogOutcome<void>>(
      context,
      (_) => ReasonDialog<void>(
        title: '공지를 지울까요?',
        body: '"${item.title}" 공지와 댓글이 모두 지워지고 되돌릴 수 없어요. 작업 기록에 사유가 남고, 사유는 필수예요.',
        confirmLabel: '지우기',
        danger: true,
        onSubmit: (reason) async => (await controller.delete(item.id, reason), null),
      ),
    );
    if (outcome?.$1 == ActionResult.done && context.mounted) AdminToast.show(context, '공지를 지웠어요');
  }
}

class _Rows extends StatelessWidget {
  const _Rows({required this.list, required this.onMore, required this.onDelete});

  final NoticeListState list;
  final VoidCallback onMore;
  final ValueChanged<NoticeItem> onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminTable(
          key: const ValueKey('notice-table'),
          columns: const [160, 220, 260, 120, 80, 120],
          fillLast: true, // 단추 칸이 남는 폭을 쓴다(최소 창 1280 에서도 넘치지 않게)
          heads: const ['올린 시각', '제목', '내용', '상태', '그림', ''],
          rows: [
            for (final item in list.items)
              AdminTableRow(
                rowKey: ValueKey('notice-row-${item.id}'),
                cells: [
                  AdminCellText(formatSubmittedAt(item.createdAt)),
                  AdminCellText(item.title),
                  AdminCellText(item.firstLine),
                  item.blinded ? const StatusBadge('가려짐', tone: StatusTone.danger) : const StatusBadge('보임'),
                  AdminCellText(item.imageUrl == null ? missingValue : '있음'),
                  AdminButton(label: '지우기', variant: AdminButtonVariant.secondary, height: 36, onPressed: () => onDelete(item)),
                ],
              ),
          ],
        ),
        if (list.moreFailed) ...[const SizedBox(height: AdminSpacing.sm), const ErrorRow('더 불러오지 못했어요. 다시 시도해 주세요.')],
        if (list.hasMore) ...[
          const SizedBox(height: AdminSpacing.md),
          Center(
            child: AdminButton(label: '더 보기', variant: AdminButtonVariant.secondary, loading: list.loadingMore, onPressed: onMore),
          ),
        ],
        const SizedBox(height: AdminSpacing.lg),
        Text('최근 순 · 20건씩 · 가린 공지도 보여요', style: AdminTypography.xs.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted)),
      ],
    );
  }
}
