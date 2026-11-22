import 'dart:math' as math;

import 'package:campus_mate_admin/api/list_page.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/tap_box.dart';
import 'package:flutter/material.dart';

/// 표 아래 번호 쪽 나누기: 왼쪽 "전체 N건", 1건 이상이면 `이전  1 2 … 10  다음`(한 쪽뿐이면 `이전 [1] 다음`, 이전 · 다음 꺼짐).
/// 번호는 10개씩 묶는다(13쪽이면 11~20). 이전 = 앞 묶음 마지막 쪽, 다음 = 다음 묶음 첫 쪽 — 첫 · 끝 묶음에서는 꺼진다.
/// 지금 쪽은 web-primary-wash 바탕 · primary-text 글자로 강조하고 눌러도 아무 일 없다. pen 에 없는 부품이라 칩 · 단추 토큰을 그대로 쓴다.
class AdminPager extends StatelessWidget {
  const AdminPager({super.key, required this.total, required this.page, required this.size, required this.onPage});

  final int total;
  final int page;
  final int size;
  final ValueChanged<int> onPage;

  static const int group = 10;

  @override
  Widget build(BuildContext context) {
    final pages = lastPage(total, size);
    final first = (page - 1) ~/ group * group + 1;
    final last = math.min(first + group - 1, pages);
    // 넓은 표 아래에서는 한 줄(왼쪽 건수 · 오른쪽 번호, 높이 36 = 칩), 좁은 칸(검수 목록 320)에서는 번호가 다음 줄로 접힌다.
    // 부모 폭을 다 쓴다(세로 목록 안에 둔다) — 그래야 건수는 왼쪽, 번호는 오른쪽 끝에 놓인다.
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: double.infinity, minHeight: AdminSizes.chip),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: AdminSpacing.xs,
        children: [
          Text(
            '전체 ${_grouped(total)}건',
            key: const ValueKey('pager-total'),
            style: AdminTypography.sm.copyWith(height: AdminTypography.smBox, color: AdminColors.muted),
          ),
          if (total > 0) // 한 쪽뿐이어도 `이전 [1] 다음` 을 보인다(사용자 요청 11-22), 0건일 때만 숨긴다
            Wrap(
              runSpacing: AdminSpacing.xxs,
              children: [
                _Cell(key: const ValueKey('pager-prev'), label: '이전', onTap: first > 1 ? () => onPage(first - 1) : null),
                for (var n = first; n <= last; n++)
                  _Cell(key: ValueKey('pager-page-$n'), label: '$n', current: n == page, onTap: n == page ? null : () => onPage(n)),
                _Cell(key: const ValueKey('pager-next'), label: '다음', onTap: last < pages ? () => onPage(last + 1) : null),
              ],
            ),
        ],
      ),
    );
  }

  static String _grouped(int n) => '$n'.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}

class _Cell extends StatelessWidget {
  const _Cell({super.key, required this.label, required this.onTap, this.current = false});

  final String label;
  final VoidCallback? onTap;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final color = current ? AdminColors.primaryText : (onTap == null ? AdminColors.disabled : AdminColors.body);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AdminSpacing.xxs / 2),
      child: TapBox(
        onTap: onTap,
        color: current ? AdminColors.primaryWash : Colors.transparent,
        cursor: SystemMouseCursors.click,
        selected: current,
        height: AdminSizes.chip,
        padding: const EdgeInsets.symmetric(horizontal: AdminSpacing.sm),
        child: Center(
          widthFactor: 1,
          child: Text(label, style: (current ? AdminTypography.smStrong : AdminTypography.sm).copyWith(color: color)),
        ),
      ),
    );
  }
}
