import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 하트 과제 줄 오른쪽의 알약(pen Status `e2aMg` · Action `xGTbF`, 검수 대기 줄 배지 SaMDZ) — 72×28 이상, 글자를 키우면 늘어난다.
/// 18a 줄([HeartTaskRow])과 검수 대기 블록([HeartTaskPendingList])이 같이 쓴다.
class HeartTaskChip extends StatelessWidget {
  const HeartTaskChip({
    required this.label,
    required this.background,
    required this.foreground,
    this.leading,
    this.minWidth = 72,
    this.labelStyle,
    super.key,
  });

  final String label;
  final Color background;
  final Color foreground;
  final Widget? leading;

  /// "제출하기" Action 은 84(값표 pVxvl).
  final double minWidth;

  /// 비우면 배지 글자(11/700, [foreground]). "제출하기" 는 14/600.
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    final leading = this.leading;
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth, minHeight: 28),
      child: DecoratedBox(
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppRadius.pill)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (leading != null) ...[leading, const SizedBox(width: 4)],
              Text(label, style: labelStyle ?? AppTypography.badge.copyWith(fontWeight: FontWeight.w700, color: foreground)),
            ],
          ),
        ),
      ),
    );
  }
}
