import 'package:campus_mate_admin/heart_tasks/heart_task_item.dart' show formatSubmittedAt;
import 'package:campus_mate_admin/inquiries/inquiry_controller.dart';
import 'package:campus_mate_admin/inquiries/inquiry_item.dart';
import 'package:campus_mate_admin/state/paged_controller.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_chip.dart';
import 'package:campus_mate_admin/widgets/admin_table.dart';
import 'package:campus_mate_admin/widgets/error_row.dart';
import 'package:campus_mate_admin/widgets/load_states.dart';
import 'package:campus_mate_admin/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 문의 상태 → 배지 색: 새 문의 warning(처리할 일) · 처리 중 primary · 답변 완료 success
StatusTone inquiryStatusTone(InquiryStatus status) {
  return switch (status) {
    InquiryStatus.newInquiry => StatusTone.warning,
    InquiryStatus.inProgress => StatusTone.primary,
    InquiryStatus.answered => StatusTone.success,
  };
}

/// 문의 목록(`/inquiries`). pen 에 문의 화면이 없어 신고 목록(A4)의 틀을 그대로 따른다: 내용 32 안쪽, 필터 칩 줄(제자리) → 24 →
/// 표(머리 44 · 줄 52 — 접수 시각 160 · 사유 130 · 보낸 사람 220 · 상태 130 · 내용은 남는 폭) → (더 보기) → 안내. 줄을 누르면 상세 `/inquiries/{id}`.
class InquiryListScreen extends ConsumerWidget {
  const InquiryListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(inquiryFilterProvider);
    final list = ref.watch(inquiryListProvider);
    final controller = ref.read(inquiryListProvider.notifier);
    final Widget body;
    if (list.loading) {
      body = const LoadingBlock('문의를 불러오고 있어요');
    } else if (list.failed) {
      body = ErrorBlock('문의를 불러오지 못했어요', onRetry: controller.retry);
    } else if (list.items.isEmpty) {
      body = EmptyBlock(status == InquiryStatus.newInquiry ? '새 문의가 없어요' : '조건에 맞는 문의가 없어요');
    } else {
      body = _Rows(list: list, onMore: controller.loadMore, onOpen: (item) => context.go('/inquiries/${item.id}', extra: item));
    }
    return Padding(
      padding: const EdgeInsets.all(AdminSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Filters(status: status, onSelect: ref.read(inquiryFilterProvider.notifier).set),
          const SizedBox(height: AdminSpacing.lg),
          Expanded(child: SingleChildScrollView(child: body)),
        ],
      ),
    );
  }
}

/// 필터 줄: 전체 + 상태 칩 3, 사이 8(신고 목록과 같은 Web/Chip). 같은 칩을 다시 눌러도 새 값이라 목록을 새로 받는다.
class _Filters extends StatelessWidget {
  const _Filters({required this.status, required this.onSelect});

  final InquiryStatus? status;
  final ValueChanged<InquiryStatus?> onSelect;

  @override
  Widget build(BuildContext context) {
    final options = <(String, InquiryStatus?)>[('전체', null), for (final s in InquiryStatus.values) (s.label, s)];
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, (label, value)) in options.indexed) ...[
            if (i > 0) const SizedBox(width: AdminSpacing.xs),
            AdminChip(label: label, selected: status == value, onTap: () => onSelect(value)),
          ],
        ],
      ),
    );
  }
}

class _Rows extends StatelessWidget {
  const _Rows({required this.list, required this.onMore, required this.onOpen});

  final PagedState<InquiryItem> list;
  final VoidCallback onMore;
  final ValueChanged<InquiryItem> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminTable(
          key: const ValueKey('inquiry-table'),
          columns: const [160, 130, 220, 130, 360],
          fillLast: true, // 내용이 남는 폭을 쓴다
          heads: const ['접수 시각', '사유', '보낸 사람', '상태', '내용'],
          rows: [
            for (final item in list.items)
              AdminTableRow(
                rowKey: ValueKey('inquiry-row-${item.id}'),
                onTap: () => onOpen(item),
                cells: [
                  AdminCellText(formatSubmittedAt(item.createdAt)),
                  AdminCellText(inquiryReasonLabel(item.reason)),
                  AdminCellText(item.writerLabel),
                  StatusBadge(item.status.label, tone: inquiryStatusTone(item.status)),
                  AdminCellText(item.firstLine),
                ],
              ),
          ],
        ),
        if (list.hasMore) ...[
          const SizedBox(height: AdminSpacing.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (list.moreFailed) ...[
                  const ErrorRow('더 불러오지 못했어요. 다시 시도해 주세요.', lineHeight: AdminTypography.xsBox),
                  const SizedBox(height: AdminSpacing.xs),
                ],
                AdminButton(label: '더 보기', variant: AdminButtonVariant.secondary, loading: list.loadingMore, onPressed: onMore),
              ],
            ),
          ),
        ],
        const SizedBox(height: AdminSpacing.lg),
        Text('최근 순 · 50건씩', style: AdminTypography.xs.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted)),
      ],
    );
  }
}
