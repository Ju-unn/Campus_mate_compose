import 'package:flutter/material.dart';

/// 흐르는 속도(px/초). pen 값 아님, 판단 — "느리게"(사용자 결정 2026-09-26, 사람 레일에서 정해 칩 줄도 같이 쓴다).
const double _pixelsPerSecond = 20;

/// 홈 줄 자동 흐름 — 사람 레일(pen `mw7Gv`)과 참여 대학 칩 줄(`yo9JJ`)이 같이 쓴다(대장 10-15).
/// [cycle] 한 벌(뒤 간격 포함)을 화면 폭을 덮고도 한 벌이 남게 이어 붙여 끝없이 오른쪽으로 흐른다.
/// 누르고 있으면(칸 사이 틈 포함) 멈추고 떼면 이어서 흐른다. 기기 "애니메이션 줄이기"가 켜져 있으면 제자리에 멈춰 있고,
/// 가로로 밀면 손이 간 만큼 움직인다(DESIGN §8.9 "손으로 밀 수는 있게 남긴다"). 세로 밀기는 받지 않아 홈 목록 스크롤은 그대로다.
/// 화면 읽기는 멈춰 있을 때 x0 에 오는 둘째 벌만 읽는다 — 복사본까지 읽으면 같은 말을 되풀이한다.
/// 높이는 한 벌의 가장 높은 칸을 따른다(글자를 키우면 늘어난다).
class AutoMarquee extends StatefulWidget {
  const AutoMarquee({required this.cycle, this.cycleWidth, super.key});

  /// 한 벌. 같은 위젯을 여러 번 그리므로 안에 GlobalKey 를 두지 않는다.
  final Widget cycle;

  /// 한 벌 폭을 미리 알면 준다(레일 — 칸 폭이 글자 배율과 상관없다). 모르면(글자 칩) 첫 프레임에 그린 뒤 잰다.
  final double? cycleWidth;

  @override
  State<AutoMarquee> createState() => _AutoMarqueeState();
}

class _AutoMarqueeState extends State<AutoMarquee> with SingleTickerProviderStateMixin {
  late final AnimationController _flow = AnimationController(vsync: this);
  final GlobalKey _firstCycle = GlobalKey();
  double? _measured;

  /// 저절로 흐르지 않는 때 — 기기 "애니메이션 줄이기" 또는 화면 읽기(스크린리더) 켜짐(WCAG 2.2.2 움직임 멈춤).
  /// 이때만 손으로 밀 수 있다.
  bool _reduceMotion = false;

  /// 줄을 누르고 있는 손가락 수. 모두 뗐을 때(0)만 다시 흐른다.
  int _pointersDown = 0;

  /// 한 벌 폭. 아직 모르거나 0 이하(그릴 것이 없음)면 null — 흐르지도 밀리지도 않고 두 벌만 그린다(0 으로 나누지 않게).
  double? get _width {
    final width = widget.cycleWidth ?? _measured;
    if (width == null || width <= 0) return null;
    return width;
  }

  void _sync() {
    final width = _width;
    if (width == null || _reduceMotion || _pointersDown > 0) {
      _flow.stop();
      return;
    }
    final duration = Duration(milliseconds: (width / _pixelsPerSecond * 1000).round());
    if (_flow.duration != duration) {
      _flow
        ..stop()
        ..duration = duration;
    }
    if (!_flow.isAnimating) _flow.repeat(); // 멈춘 자리에서 이어서 흐른다.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context) || MediaQuery.accessibleNavigationOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(AutoMarquee oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  /// 폭을 모르는 한 벌은 그린 뒤 첫 벌의 폭을 잰다. 다시 그릴 때마다(글자 배율 · 칩이 바뀜) 다시 재고, 같으면 그대로 둔다.
  void _measure(Duration _) {
    if (!mounted) return;
    final width = (_firstCycle.currentContext?.findRenderObject() as RenderBox?)?.size.width;
    if (width == null || (width - (_measured ?? -1)).abs() < 0.5) return;
    setState(() => _measured = width);
    _sync();
  }

  void _press(int delta) {
    // Listener 는 자기가 down 을 받은 포인터의 up·cancel 만 받는다 — 0 아래로 내려가지 않는다.
    _pointersDown += delta;
    _sync();
  }

  /// 손으로 민 거리만큼 옮긴다. 흐름과 같은 값(한 벌 = 0~1)을 쓰고 한 벌 길이로 나눈 나머지라 끝없이 되풀이된다.
  void _drag(DragUpdateDetails details) {
    final width = _width;
    if (width == null) return;
    _flow.value = (_flow.value + details.delta.dx / width) % 1.0;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cycleWidth == null) WidgetsBinding.instance.addPostFrameCallback(_measure);
    final width = _width;
    // 화면 폭을 덮고도 한 벌이 남게 복사한다 — 한 벌만큼 흘러가면 처음 자리로 돌아가도 이음매가 안 보인다.
    // 폭을 재기 전(첫 프레임)에는 두 벌만 그린다.
    final copies = width == null ? 2 : (MediaQuery.sizeOf(context).width / width).ceil() + 1;
    // 가로 밀기는 동작 줄이기에서만 받는다 — 흐르는 중에는 누르면 멈추는 것으로 충분하다(pen `P2sFxR` 메모).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: _reduceMotion ? _drag : null,
      child: Listener(
        // 칸 사이 틈에는 그림이 없어 자식이 맞지 않는다 — 줄 전체가 누름을 받는다.
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _press(1),
        onPointerUp: (_) => _press(-1),
        onPointerCancel: (_) => _press(-1),
        child: UnconstrainedBox(
          constrainedAxis: Axis.vertical,
          alignment: Alignment.centerLeft,
          clipBehavior: Clip.hardEdge,
          child: AnimatedBuilder(
            animation: _flow,
            // 멈춰 있을 때(값 0) 둘째 벌이 x0 에 온다.
            builder: (context, child) =>
                Transform.translate(offset: Offset(width == null ? 0 : (_flow.value - 1) * width, 0), child: child),
            // 줄 묶음을 한 번 그려 두고 매 프레임 옮기기만 한다 — 경계가 없으면 프레임마다 그림을 다시 그린다.
            child: RepaintBoundary(
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var copy = 0; copy < copies; copy++)
                      KeyedSubtree(
                        key: copy == 0 ? _firstCycle : null,
                        child: ExcludeSemantics(excluding: copy != 1, child: widget.cycle),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
