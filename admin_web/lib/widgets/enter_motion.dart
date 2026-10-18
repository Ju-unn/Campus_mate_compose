import 'package:campus_mate_admin/theme/admin_motion.dart';
import 'package:flutter/widgets.dart';

/// 처음 그려질 때 한 번, 투명 · [AdminMotion.rise] 아래에서 [AdminMotion.enter] 동안 제자리로 온다(관문 카드).
/// 투명도와 위치(transform)만 움직인다. 동작 줄이기면 그대로 그린다.
class EnterMotion extends StatelessWidget {
  const EnterMotion({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (AdminMotion.reduced(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AdminMotion.enter,
      curve: AdminMotion.curve,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(offset: Offset(0, AdminMotion.rise * (1 - value)), child: child),
      ),
    );
  }
}
