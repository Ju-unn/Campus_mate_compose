import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:flutter/material.dart';

/// 처음 그려질 때 한 번, 투명 · 아래 [rise] · 크기 [scaleFrom] 에서 제자리로 온다(DESIGN §7).
/// transform · opacity 만 바꾼다 — 자리는 처음부터 최종 크기로 잡혀 레이아웃이 흔들리지 않고, 움직이는 중에도 누를 수 있다.
/// [curve] 는 움직임(위치 · 크기)에만 쓰고 투명도는 늘 `{motion.standard}` 커브다 — emphasis(easeOutBack)가 1 을 넘어도 투명도는 넘지 않는다.
/// 기기 "동작 줄이기"이거나 [enabled] 가 false 면 처음부터 최종 상태다.
class Entrance extends StatefulWidget {
  const Entrance({
    required this.child,
    this.rise = 0,
    this.scaleFrom = 1,
    this.duration = AppMotion.standard,
    this.curve = AppMotion.standardCurve,
    this.delay = Duration.zero,
    this.enabled = true,
    super.key,
  });

  final Widget child;

  /// 시작 때 아래로 내려가 있는 거리(px)
  final double rise;

  /// 시작 크기 배율(1 = 그대로)
  final double scaleFrom;
  final Duration duration;
  final Curve curve;

  /// 시작 전 기다리는 시간 — 블록 사이 간격(stagger)
  final Duration delay;
  final bool enabled;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.delay + widget.duration);
  late final double _start = widget.delay.inMicroseconds / _controller.duration!.inMicroseconds;
  late final Animation<double> _move = CurvedAnimation(parent: _controller, curve: Interval(_start, 1, curve: widget.curve));
  late final Animation<double> _fade =
      CurvedAnimation(parent: _controller, curve: Interval(_start, 1, curve: AppMotion.standardCurve));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!widget.enabled || MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      return;
    }
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final move = _move.value;
        final scale = widget.scaleFrom + (1 - widget.scaleFrom) * move;
        return Opacity(
          opacity: _fade.value.clamp(0.0, 1.0),
          // 투명한 첫 프레임에도 스크린리더가 내용을 읽고 누를 수 있다 — 꾸밈 효과가 내용을 가리지 않는다.
          alwaysIncludeSemantics: true,
          // 가운데를 기준으로 키우고 [rise] 만큼 내린다(이동 · 크기 한 행렬).
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(0, widget.rise * (1 - move), 0),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
