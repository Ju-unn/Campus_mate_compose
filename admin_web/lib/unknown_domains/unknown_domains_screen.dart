import 'package:campus_mate_admin/heart_tasks/heart_task_item.dart' show formatSubmittedAt;
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/unknown_domains/unknown_domains_controller.dart';
import 'package:campus_mate_admin/widgets/admin_table.dart';
import 'package:campus_mate_admin/widgets/load_states.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A6 미등록 학교 메일(pen mGKkm · 1440×900). 내용 32 안쪽, 세로 24: 표(머리 44 · 줄 52 — 메일 도메인 300 · 시도 횟수 140 · 마지막 시도 220) → 안내.
/// 읽기 전용 — 줄은 눌리지 않는다. 많은 순은 서버가 정해 준 대로.
class UnknownDomainsScreen extends ConsumerWidget {
  const UnknownDomainsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final domains = ref.watch(unknownDomainsProvider);
    final Widget body;
    if (domains.hasError) {
      body = ErrorBlock('미등록 학교 메일을 불러오지 못했어요', onRetry: ref.read(unknownDomainsProvider.notifier).retry);
    } else if (!domains.hasValue) {
      body = const LoadingBlock('미등록 학교 메일을 불러오고 있어요');
    } else if (domains.requireValue.isEmpty) {
      body = const EmptyBlock('미등록 학교 메일 시도가 없어요');
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminTable(
            key: const ValueKey('domain-table'),
            columns: const [300, 140, 220],
            heads: const ['메일 도메인', '시도 횟수', '마지막 시도'],
            rows: [
              for (final domain in domains.requireValue)
                AdminTableRow(
                  rowKey: ValueKey('domain-row-${domain.domain}'),
                  cells: [
                    AdminCellText(domain.domain),
                    AdminCellText('${domain.attemptCount}회'),
                    AdminCellText(formatSubmittedAt(domain.lastSeenAt)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AdminSpacing.lg),
          Text('많은 순으로 보여요. 읽기 전용이에요.', style: AdminTypography.xs.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted)),
        ],
      );
    }
    return Padding(padding: const EdgeInsets.all(AdminSpacing.xl), child: SingleChildScrollView(child: body));
  }
}
