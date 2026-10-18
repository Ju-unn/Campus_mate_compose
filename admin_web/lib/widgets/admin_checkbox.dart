import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/tap_box.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// pen Web/Checkbox(켬 A2mVU · 끔 kwu5q, PNG A4_조치_완료 · A4_기각_대화상자 측정): 줄 높이 20 — 상자 18 · 모서리 4 ·
/// web-surface 바탕 · 테두리 1.5(켬 web-primary + check 12 web-primary, 끔 web-outline-strong) → 10 → 글자 14 web-ink.
/// 줄 전체가 눌린다. 끔 상태는 PNG 가 없어 켬의 테두리 색만 바꿨다(대장 보고표).
/// 잠긴 켬(Web/Checkbox · On · Disabled IovNE, A4 기각 대화상자 U90Ugj): 상자 테두리 · 체크 web-disabled, 글자 web-muted.
/// 잠긴 끔은 시안이 없어 평소 끔 그대로 둔다.
class AdminCheckbox extends StatelessWidget {
  const AdminCheckbox({super.key, required this.label, required this.value, required this.onChanged});

  /// 상자 18 + 사이 10 — 체크 아래 안내 글을 체크 글자 시작에 맞출 때
  static const double labelInset = 18 + 10;

  final String label;
  final bool value;

  /// null 이면 잠김(처리 중 · 다른 체크가 대신할 때)
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    final lockedOn = value && onChanged == null;
    final color = !value ? AdminColors.outlineStrong : (lockedOn ? AdminColors.disabled : AdminColors.primary);
    return TapBox(
      onTap: onChanged == null ? null : () => onChanged(!value),
      checked: value,
      radius: 4,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              key: const ValueKey('checkbox-box'),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: AdminColors.surface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color, width: 1.5),
              ),
              child: value ? Icon(LucideIcons.check, size: 12, color: color) : null,
            ),
            const SizedBox(width: 10), // PNG 측정 — 간격 표에 없는 값
            Flexible(
              child: Text(
                label,
                style: AdminTypography.sm.copyWith(height: AdminTypography.smBox, color: lockedOn ? AdminColors.muted : AdminColors.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
