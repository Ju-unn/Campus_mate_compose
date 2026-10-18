import 'package:campus_mate_admin/theme/admin_motion.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 요청 중 · 판정 중 표시(pen Web/Button 상태줄 · 공통_판정_중): Lucide loader-circle 16 이 1초에 한 바퀴 일정하게 돈다.
/// pen 은 멈춘 그림이다 — 동작 줄이기면 pen 그대로 멈춰 둔다.
class AdminLoader extends StatefulWidget {
  const AdminLoader({super.key, required this.color, this.size = 16});

  final Color color;
  final double size;

  @override
  State<AdminLoader> createState() => _AdminLoaderState();
}

class _AdminLoaderState extends State<AdminLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _turns = AnimationController(vsync: this, duration: AdminMotion.spin);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AdminMotion.reduced(context)) {
      _turns.stop();
      return;
    }
    if (!_turns.isAnimating) _turns.repeat();
  }

  @override
  void dispose() {
    _turns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = Icon(LucideIcons.loaderCircle, size: widget.size, color: widget.color);
    if (AdminMotion.reduced(context)) return icon;
    return RotationTransition(turns: _turns, child: icon);
  }
}
