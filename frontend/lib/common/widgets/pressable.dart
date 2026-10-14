import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:flutter/material.dart';

/// 카드형 누를 곳의 눌림 반응(DESIGN §7 — `{motion.press}` 120ms, 투명도만 바꾸고 크기 · 자리는 고정).
/// 잉크(InkWell)를 쓰지 않는다 — 잉크는 가장 가까운 Material 에 좌표로 그려 스크롤 뒤에 떠 남는다(COMMON 4-2).
/// 기기 "동작 줄이기"면 투명도는 그대로 바뀌고 시간만 0 이다.
class Pressable extends StatefulWidget {
  const Pressable({required this.onTap, required this.child, super.key});

  /// 눌렸을 때 투명도. pen · DESIGN 에 값이 없어 정한 값이다(보고 · 확인 대상).
  static const double pressedOpacity = 0.7;

  final VoidCallback onTap;
  final Widget child;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _press(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => _press(true),
        onTapUp: (_) => _press(false),
        onTapCancel: () => _press(false),
        child: AnimatedOpacity(
          opacity: _pressed ? Pressable.pressedOpacity : 1,
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppMotion.press,
          curve: AppMotion.pressCurve,
          child: widget.child,
        ),
      ),
    );
  }
}
