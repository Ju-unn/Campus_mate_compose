import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_motion.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:flutter/material.dart';

/// 관리자 대화상자를 띄운다: 전체 web-scrim, 200ms 에 투명도로 나타나고 사라진다(관문 카드와 같은 토큰).
/// Material DialogRoute 는 사라질 때도 같은 시간을 쓴다(reverseDuration 을 읽지 않음) — 대신 사라질 때는 곡선을 뒤집어
/// 빠르게 시작한다. 동작 줄이기면 바로. Esc · 바깥 누름으로 닫힌다.
Future<T?> showAdminDialog<T>(BuildContext context, WidgetBuilder builder) {
  return showDialog<T>(
    context: context,
    barrierColor: AdminColors.scrim,
    animationStyle: AdminMotion.reduced(context)
        ? AnimationStyle.noAnimation
        : AnimationStyle(duration: AdminMotion.enter, curve: AdminMotion.curve, reverseCurve: AdminMotion.curve.flipped),
    builder: builder,
  );
}

/// pen Web/Dialog(p8OOG · 공통_이미_처리됨_409 Z3Xg7O): 폭 480 · 안쪽 24 · 세로 간격 16 · 모서리 14 · web-surface ·
/// 제목 20/700 → 설명 14 web-muted(줄 1.5) → 오른쪽 끝 주 단추 하나.
class AdminDialog extends StatelessWidget {
  const AdminDialog({super.key, required this.title, required this.body, this.confirmLabel = '확인'});

  final String title;
  final String body;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        key: const ValueKey('admin-dialog'),
        color: AdminColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AdminRadius.md)),
        child: SizedBox(
          width: 480,
          child: Padding(
            padding: const EdgeInsets.all(AdminSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(header: true, child: Text(title, style: AdminTypography.lg.copyWith(color: AdminColors.ink))),
                const SizedBox(height: AdminSpacing.md),
                Text(body, style: AdminTypography.sm.copyWith(color: AdminColors.muted)),
                const SizedBox(height: AdminSpacing.md),
                Align(
                  alignment: Alignment.centerRight,
                  child: AdminButton(label: confirmLabel, onPressed: () => Navigator.of(context).pop()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
