import 'package:campus_mate_admin/heart_tasks/heart_task_item.dart' show formatSubmittedAt;
import 'package:campus_mate_admin/providers.dart';
import 'package:campus_mate_admin/reports/report_controller.dart';
import 'package:campus_mate_admin/reports/report_item.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_chip.dart';
import 'package:campus_mate_admin/widgets/admin_loader.dart';
import 'package:campus_mate_admin/widgets/status_badge.dart';
import 'package:campus_mate_admin/widgets/table_empty.dart';
import 'package:campus_mate_admin/widgets/tap_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 신고 상태 → 배지 색(pen ⑤): 대기 warning · 조치 success · 기각 surface-strong + muted
StatusTone reportStatusTone(ReportStatus status) {
  return switch (status) {
    ReportStatus.open => StatusTone.warning,
    ReportStatus.actioned => StatusTone.success,
    ReportStatus.dismissed => StatusTone.neutral,
  };
}

/// A4 신고 목록(pen i5AYYB · 1440×900). 내용 32 안쪽: 필터 줄(MhNyJ) → 24 → 표(gVa8u) → 24 → "오래된 순 · 최대 50건".
/// 필터 줄은 제자리, 표 · 안내만 세로로 스크롤한다(최대 50줄). 줄을 누르면 그 신고의 상세 주소(/reports/{id}).
class ReportListScreen extends ConsumerWidget {
  const ReportListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(reportFilterProvider);
    final items = ref.watch(reportListProvider);
    final now = ref.watch(clockProvider)();
    final Widget content;
    if (items.hasError) {
      content = AdminTableEmpty(
        framed: false,
        leading: const Icon(LucideIcons.circleAlert, size: 32, color: AdminColors.danger),
        title: '목록을 불러오지 못했어요',
        body: '인터넷 연결을 확인하고 다시 시도해 주세요.',
        action: AdminButton(
          label: '다시 시도',
          variant: AdminButtonVariant.secondary,
          onPressed: ref.read(reportListProvider.notifier).reload,
        ),
        alert: true,
      );
    } else if (!items.hasValue || items.isLoading) {
      content = const AdminTableEmpty(framed: false, leading: AdminLoader(color: AdminColors.muted), body: '신고 목록을 불러오고 있어요');
    } else if (items.requireValue.isEmpty) {
      final openOnly = filter.status == ReportStatus.open && filter.type == null;
      content = AdminTableEmpty(
        leading: const Icon(LucideIcons.inbox, size: 32, color: AdminColors.disabled),
        title: openOnly ? '열린 신고가 없어요' : '조건에 맞는 신고가 없어요',
        body: openOnly ? '새 신고가 들어오면 여기에 보여요' : null,
        enter: true,
      );
    } else {
      content = Expanded(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Table(
                items: items.requireValue,
                now: now,
                onOpen: (item) => context.go('/reports/${item.id}', extra: item),
              ),
              const SizedBox(height: AdminSpacing.lg),
              Text('오래된 순 · 최대 50건', style: AdminTypography.xs.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted)),
            ],
          ),
        ),
      );
    }
    final filters = ref.read(reportFilterProvider.notifier);
    return Padding(
      padding: const EdgeInsets.all(AdminSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Filters(filter: filter, onType: filters.setType, onStatus: filters.setStatus),
          const SizedBox(height: AdminSpacing.lg),
          content,
        ],
      ),
    );
  }
}

/// 필터 줄(MhNyJ): 종류 칩 5 → 세로 구분선 1×24 web-outline(WhVIp) → 상태 칩 3, 모두 사이 8. 칩은 A3 와 같은 Web/Chip.
class _Filters extends StatelessWidget {
  const _Filters({required this.filter, required this.onType, required this.onStatus});

  final ReportFilter filter;
  final ValueChanged<ReportTargetType?> onType;
  final ValueChanged<ReportStatus> onStatus;

  @override
  Widget build(BuildContext context) {
    final types = <(String, ReportTargetType?)>[('전체', null), for (final type in ReportTargetType.values) (type.listLabel, type)];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, (label, type)) in types.indexed) ...[
          if (i > 0) const SizedBox(width: AdminSpacing.xs),
          AdminChip(label: label, selected: filter.type == type, onTap: () => onType(type)),
        ],
        const SizedBox(width: AdminSpacing.xs),
        const SizedBox(key: ValueKey('chip-divider'), width: 1, height: 24, child: ColoredBox(color: AdminColors.outline)),
        for (final status in ReportStatus.values) ...[
          const SizedBox(width: AdminSpacing.xs),
          AdminChip(label: status.label, selected: filter.status == status, onTap: () => onStatus(status)),
        ],
      ],
    );
  }
}

/// 표 열(pen 값표 ①): 대상 종류 110 · 신고 사유 170 · 신고자 수 90 · 대상 요약 230 · 접수 시각 160 · 지난 시간 150 · 상태 110.
/// 1440 에서는 남는 폭이 오른쪽에 빈다. 최소 창(1280)에서는 대상 요약만 줄어든다(합 1020 > 칸 976).
const List<double> _columns = [110, 170, 90, 230, 160, 150, 110];
const int _flexColumn = 3;

/// pen gVa8u: 폭 가득 · 모서리 14 · web-surface · web-outline 1 · 잘라냄. 머리줄(vUnj0) 44 web-surface-strong ·
/// 머리 칸(JEldh) 12/700 web-muted · 좌우 16, 줄 52 · 아래 web-hairline 1 · 칸(mV3eq) 14 web-ink · 좌우 16.
class _Table extends StatelessWidget {
  const _Table({required this.items, required this.now, required this.onOpen});

  final List<ReportSummary> items;
  final DateTime now;
  final ValueChanged<ReportSummary> onOpen;

  static const List<String> _heads = ['대상 종류', '신고 사유', '신고자 수', '대상 요약', '접수 시각', '접수 뒤 지난 시간', '상태'];

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(AdminRadius.md);
    final headStyle = AdminTypography.xs.copyWith(fontWeight: FontWeight.w700, height: AdminTypography.xsBox, color: AdminColors.muted);
    final cellStyle = AdminTypography.sm.copyWith(color: AdminColors.ink);
    return Container(
      key: const ValueKey('report-table'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: AdminColors.surface, borderRadius: shape),
      foregroundDecoration: BoxDecoration(borderRadius: shape, border: Border.all(color: AdminColors.outline)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const ValueKey('report-table-head'),
            height: 44,
            color: AdminColors.surfaceStrong,
            child: _Cells([for (final head in _heads) Text(head, maxLines: 1, overflow: TextOverflow.ellipsis, style: headStyle)]),
          ),
          for (final item in items)
            TapBox(
              key: ValueKey('report-row-${item.id}'),
              onTap: () => onOpen(item),
              radius: 0,
              height: 52,
              child: DecoratedBox(
                key: ValueKey('report-row-line-${item.id}'),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AdminColors.hairline))),
                child: _Cells([
                  for (final text in [
                    item.type.listLabel,
                    reportReasonLabel(item.reason),
                    // 같은 대상의 열린 신고자 수(서버 open_reporters). 대상 계정이 지워졌거나 옛 응답이면 "—"
                    item.target == null ? missingValue : (item.openReporters == null ? missingValue : '${item.openReporters}명'),
                    item.targetSummary,
                    formatSubmittedAt(item.createdAt),
                    formatElapsed(item.createdAt, now),
                  ])
                    Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: cellStyle),
                  StatusBadge(item.status.badgeLabel, tone: reportStatusTone(item.status)),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

/// 한 줄의 칸들 — 열 폭 [_columns], 칸 안쪽 좌우 16, 세로 가운데.
class _Cells extends StatelessWidget {
  const _Cells(this.cells);

  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (i, cell) in cells.indexed)
          if (i == _flexColumn)
            Flexible(child: _cell(_columns[i], cell))
          else
            _cell(_columns[i], cell),
      ],
    );
  }

  static Widget _cell(double width, Widget child) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AdminSpacing.md),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }
}
