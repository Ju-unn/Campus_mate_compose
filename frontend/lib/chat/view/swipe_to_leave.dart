import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// 13a 대화 줄 왼쪽 밀기(pen `zMfIn`, 결정 10 · B7). 80 밀면 멈추고 오른쪽 80 에 빨간 "나가기"(`O0ULe2`)가 드러난다.
/// 절반 넘게 밀거나 빠르게 밀면 열리고, 아니면 제자리로. 열린 줄을 누르면 닫히기만 한다(방으로 가지 않는다).
/// "나가기" 는 줄을 닫고 [onLeave] — 확인 다이얼로그 · 나가기 호출은 부른 쪽 몫이다.
/// 밀 수 없는 낭독기에는 같은 동작을 "채팅방 나가기" 사용자 동작으로 준다.
class SwipeToLeave extends StatefulWidget {
  const SwipeToLeave({required this.onLeave, required this.child, super.key});

  final Future<void> Function() onLeave;
  final Widget child;

  @override
  State<SwipeToLeave> createState() => _SwipeToLeaveState();
}

class _SwipeToLeaveState extends State<SwipeToLeave> with SingleTickerProviderStateMixin {
  /// pen 밀린 거리 = 드러나는 칸 폭 80.
  static const double _actionWidth = 80;

  late final AnimationController _open = AnimationController(vsync: this, duration: AppMotion.standard);

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  void _drag(DragUpdateDetails details) => _open.value -= details.primaryDelta! / _actionWidth;

  void _settle(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final open = velocity.abs() > 300 ? velocity < 0 : _open.value > 0.5;
    _open.animateTo(open ? 1 : 0, curve: AppMotion.standardCurve);
  }

  Future<void> _leave() async {
    _open.animateTo(0, curve: AppMotion.standardCurve);
    await widget.onLeave();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      customSemanticsActions: {const CustomSemanticsAction(label: '채팅방 나가기'): _leave},
      child: GestureDetector(
        onHorizontalDragUpdate: _drag,
        onHorizontalDragEnd: _settle,
        // pen JDeui clip — 밀린 줄이 화면 왼쪽 밖으로 그려지지 않게.
        child: ClipRect(
          child: Stack(
            children: [
              // 낭독기는 위 사용자 동작으로 받으니, 줄 뒤에 숨은 칸은 읽히지 않게 뺀다.
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: _actionWidth,
                child: ExcludeSemantics(child: _LeaveAction(onTap: _leave)),
              ),
              AnimatedBuilder(
                animation: _open,
                builder: (context, child) => Transform.translate(
                  offset: Offset(-_actionWidth * _open.value, 0),
                  child: Stack(
                    children: [
                      child!,
                      // 열려 있는 동안 줄 누름은 닫기로 받는다.
                      if (_open.value > 0)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _open.animateTo(0, curve: AppMotion.standardCurve),
                          ),
                        ),
                    ],
                  ),
                ),
                child: widget.child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 드러나는 칸(pen `O0ULe2`): #FF385C 직각, "나가기" 14/700 흰. 화살표 아이콘은 pen 에서 꺼져 있어 그리지 않는다.
class _LeaveAction extends StatelessWidget {
  const _LeaveAction({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Text('나가기', style: AppTypography.labelSmall.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}
