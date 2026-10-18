import 'package:campus_mate_admin/actions/action_item.dart';
import 'package:campus_mate_admin/actions/action_log_controller.dart';
import 'package:campus_mate_admin/heart_tasks/heart_task_item.dart' show formatSubmittedAt;
import 'package:campus_mate_admin/state/paged_controller.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_search_field.dart';
import 'package:campus_mate_admin/widgets/admin_table.dart';
import 'package:campus_mate_admin/widgets/error_row.dart';
import 'package:campus_mate_admin/widgets/load_states.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A7 작업 기록(pen RHMgk · 1440×900). 내용 32 안쪽, 세로 24: 검색칸(320×44 "대상 id 검색") → 표(머리 44 · 줄 52 — 시각 180 · 관리자 180 ·
/// 작업 150 · 대상 200 · 사유 360) → (더 보기) → 안내. 읽기 전용 · 최근 순 50건씩.
/// 검색은 대상 id 정확 일치(엔터) — UUID 모양이 아니면 요청 없이 칸 아래 오류 줄(서버 필터 문법이 끼어들 틈을 처음부터 없앤다).
class ActionLogScreen extends ConsumerStatefulWidget {
  const ActionLogScreen({super.key});

  @override
  ConsumerState<ActionLogScreen> createState() => _ActionLogScreenState();
}

class _ActionLogScreenState extends ConsumerState<ActionLogScreen> {
  final TextEditingController _query = TextEditingController();
  bool _badShape = false;

  @override
  void initState() {
    super.initState();
    _query.addListener(() {
      if (_badShape) setState(() => _badShape = false); // 고치기 시작하면 오류 줄을 거둔다
    });
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _search(String raw) {
    final text = raw.trim().toLowerCase(); // 서버 대상 id 는 소문자 UUID
    final target = text.isEmpty ? null : text;
    if (target != null && !isUuidShape(target)) {
      setState(() => _badShape = true);
      return;
    }
    // 같은 값을 다시 찾으면(엔터 한 번 더) 새로 받는다
    if (ref.read(actionTargetProvider) == target) {
      ref.invalidate(actionLogProvider);
    } else {
      ref.read(actionTargetProvider.notifier).set(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = ref.watch(actionTargetProvider);
    final list = ref.watch(actionLogProvider);
    final controller = ref.read(actionLogProvider.notifier);
    final Widget body;
    if (list.loading) {
      body = const LoadingBlock('작업 기록을 불러오고 있어요');
    } else if (list.failed) {
      body = ErrorBlock('작업 기록을 불러오지 못했어요', onRetry: controller.retry);
    } else if (list.items.isEmpty) {
      body = EmptyBlock(target == null ? '기록이 없어요' : '그 id 로 남은 기록이 없어요');
    } else {
      body = _Rows(list: list, onMore: controller.loadMore);
    }
    return Padding(
      padding: const EdgeInsets.all(AdminSpacing.xl),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                key: const ValueKey('action-search-box'),
                width: 320,
                child: AdminSearchField(controller: _query, hint: '대상 id 검색', maxChars: 64, onSubmitted: _search),
              ),
            ),
            if (_badShape) ...[
              const SizedBox(height: AdminSpacing.xs),
              const ErrorRow('id 모양이 아니에요', lineHeight: AdminTypography.xsBox),
            ],
            const SizedBox(height: AdminSpacing.lg),
            body,
          ],
        ),
      ),
    );
  }
}

class _Rows extends StatelessWidget {
  const _Rows({required this.list, required this.onMore});

  final PagedState<ActionRow> list;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminTable(
          key: const ValueKey('action-table'),
          columns: const [180, 180, 150, 200, 360],
          fillLast: true, // 긴 사유가 남는 폭을 쓴다(pen 360 은 최소)
          heads: const ['시각', '관리자', '작업', '대상', '사유'],
          rows: [
            for (final row in list.items)
              AdminTableRow(
                rowKey: ValueKey('action-row-${row.id}'),
                cells: [
                  AdminCellText(formatSubmittedAt(row.createdAt)),
                  AdminCellText(row.adminLabel),
                  AdminCellText(row.actionLabel),
                  AdminCellText(row.targetLabel),
                  AdminCellText(row.reasonLabel),
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
        Text('읽기 전용이에요. 기록은 2년 보관돼요. · 최근 순 50건씩', style: AdminTypography.xs.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted)),
      ],
    );
  }
}
