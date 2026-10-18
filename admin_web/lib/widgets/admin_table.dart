import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/tap_box.dart';
import 'package:flutter/material.dart';

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
  const AdminTable({super.key, required this.columns, required this.heads, required this.rows, this.fillLast = false});

  final List<double> columns;
  final List<String> heads;
  final List<AdminTableRow> rows;
  final bool fillLast;

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
            child: _cells([for (final head in heads) Text(head, maxLines: 1, overflow: TextOverflow.ellipsis, style: headStyle)]),
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
