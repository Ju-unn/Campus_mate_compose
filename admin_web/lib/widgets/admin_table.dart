import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/tap_box.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 머리 칸을 눌러 줄 세우기(사용자 목록, 사용자 요청 11-22). [columns] 칸만 눌리고, [current] 칸 글자 오른쪽에 화살표
/// (오름 ↑ · 내림 ↓)를 단다. 정렬 자체는 부르는 쪽(서버)이 한다 — 표는 누른 칸 번호만 알린다.
class AdminTableSort {
  const AdminTableSort({required this.columns, required this.current, required this.ascending, required this.onSort});

  final Set<int> columns;
  final int current;
  final bool ascending;
  final ValueChanged<int> onSort;
}

/// 표 한 줄. [onTap] 이 있으면 줄 전체가 눌린다(hover · 눌림은 [TapBox] — 신고 목록 줄과 같다).
class AdminTableRow {
  const AdminTableRow({required this.cells, this.onTap, this.rowKey});

  final List<Widget> cells;
  final VoidCallback? onTap;
  final Key? rowKey;
}

/// 표 칸 글자 14 web-ink — 두 줄까지(넘으면 …). 서버 글자는 이 일반 Text 로만 그린다.
class AdminCellText extends StatelessWidget {
  const AdminCellText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: AdminTypography.sm.copyWith(color: AdminColors.ink));
  }
}

/// pen Web/Table(A4 gVa8u · A5 VY7a0 · A8 AxOrD): 폭 가득 · 모서리 14 · web-surface · web-outline 1 · 잘라냄. 머리줄 44 web-surface-strong ·
/// 머리 칸(JEldh) 12/700 web-muted · 좌우 16, 줄 52 · 아래 web-hairline 1 · 칸(mV3eq) 14 web-ink · 좌우 16.
/// 열 폭은 [columns]. [fillLast] 면 마지막 열이 남는 폭을 채운다(A5 상세 · A8 못 거둔 표).
class AdminTable extends StatelessWidget {
  const AdminTable({super.key, required this.columns, required this.heads, required this.rows, this.fillLast = false, this.sort});

  final List<double> columns;
  final List<String> heads;
  final List<AdminTableRow> rows;
  final bool fillLast;

  /// 머리 칸 정렬. null 이면 머리 칸은 글자뿐이다(다른 표는 그대로).
  final AdminTableSort? sort;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(AdminRadius.md);
    final headStyle = AdminTypography.xs.copyWith(fontWeight: FontWeight.w700, height: AdminTypography.xsBox, color: AdminColors.muted);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: AdminColors.surface, borderRadius: shape),
      foregroundDecoration: BoxDecoration(borderRadius: shape, border: Border.all(color: AdminColors.outline)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 44,
            color: AdminColors.surfaceStrong,
            child: _cells([
              for (final (i, head) in heads.indexed)
                if (sort case final sort? when sort.columns.contains(i))
                  _SortHead(head: head, style: headStyle, sort: sort, index: i)
                else
                  Text(head, maxLines: 1, overflow: TextOverflow.ellipsis, style: headStyle),
            ]),
          ),
          for (final row in rows) _row(row),
        ],
      ),
    );
  }

  Widget _row(AdminTableRow row) {
    final line = DecoratedBox(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AdminColors.hairline))),
      child: _cells(row.cells),
    );
    final onTap = row.onTap;
    if (onTap == null) return SizedBox(key: row.rowKey, height: 52, child: line);
    return TapBox(key: row.rowKey, onTap: onTap, radius: 0, height: 52, child: line);
  }

  Widget _cells(List<Widget> cells) {
    Widget cell(double? width, Widget child) {
      final inner = Padding(
        padding: const EdgeInsets.symmetric(horizontal: AdminSpacing.md),
        child: Align(alignment: Alignment.centerLeft, child: child),
      );
      return width == null ? Expanded(child: inner) : SizedBox(width: width, child: inner);
    }

    return Row(
      children: [
        for (final (i, child) in cells.indexed) cell(fillLast && i == cells.length - 1 ? null : columns[i], child),
      ],
    );
  }
}

/// 누를 수 있는 머리 칸: 글자(머리 칸 글꼴 그대로) + 지금 정렬 칸이면 화살표 14 web-ink. pen 에 없는 부품이라 머리 칸 토큰 · [TapBox]
/// (올림 · 누름 덧칠 · 키보드 초점 테두리)를 그대로 쓴다. 화면 읽기는 "칸 이름, 방향" 을 단추로 읽고 지금 칸은 고름으로 알린다.
class _SortHead extends StatelessWidget {
  const _SortHead({required this.head, required this.style, required this.sort, required this.index});

  final String head;
  final TextStyle style;
  final AdminTableSort sort;
  final int index;

  @override
  Widget build(BuildContext context) {
    final current = sort.current == index;
    final state = !current ? '눌러서 정렬' : (sort.ascending ? '오름차순 정렬됨' : '내림차순 정렬됨');
    return TapBox(
      onTap: () => sort.onSort(index),
      cursor: SystemMouseCursors.click,
      selected: current,
      semanticLabel: '$head, $state',
      height: 32,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(head, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
            if (current) ...[
              const SizedBox(width: AdminSpacing.xxs),
              Icon(sort.ascending ? LucideIcons.arrowUp : LucideIcons.arrowDown, size: 14, color: AdminColors.ink),
            ],
          ],
        ),
      ),
    );
  }
}
