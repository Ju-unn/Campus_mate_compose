import 'package:campus_mate/home/view/mosaic_tile.dart';
import 'package:flutter/material.dart';

/// 칸 사이 간격(pen `P2sFxR` gap).
const double _gap = 10;

/// 흐르는 속도(px/초). pen 값 아님, 판단 — "느리게"(사용자 결정 2026-09-26).
const double _pixelsPerSecond = 20;

/// mosaic-rail(pen `P2sFxR`). 사람 칸 뒤에 빈 칸 하나를 붙인 한 벌을 끝없이 되풀이하며 오른쪽으로 흐른다.
/// 누르고 있으면 멈추고 떼면 이어서 흐른다. 기기 "애니메이션 줄이기"가 켜져 있으면 pen 자리에 멈춰 있다.
/// 높이는 칸 중 가장 높은 것을 따른다 — 배율 1.0 에서 140, 글자를 키우면 빈 칸 글자만큼 늘어난다.
/// ponytail: 한 벌을 화면 폭만큼 복사해 Row 로 한 번에 그린다. 사람이 수십 명이 되면 높이를 배율로 계산해 ListView 로 바꾼다.
class MosaicRail extends StatefulWidget {
  const MosaicRail({required this.images, super.key});

  final List<String> images;

  @override
  State<MosaicRail> createState() => _MosaicRailState();
}

class _MosaicRailState extends State<MosaicRail> with SingleTickerProviderStateMixin {
  late final AnimationController _flow = AnimationController(vsync: this, duration: _cycleDuration);
  bool _reduceMotion = false;
  /// 레일을 누르고 있는 손가락 수. 모두 뗐을 때(0)만 다시 흐른다.
  int _pointersDown = 0;

  /// 한 벌 폭. 칸 폭이 글자 배율과 상관없어 미리 안다.
  double get _cycleWidth => (widget.images.length + 1) * (mosaicTileWidth + _gap);

  Duration get _cycleDuration => Duration(milliseconds: (_cycleWidth / _pixelsPerSecond * 1000).round());

  void _sync() {
    if (_reduceMotion || _pointersDown > 0) {
      _flow.stop();
    } else if (!_flow.isAnimating) {
      _flow.repeat(); // 멈춘 자리에서 이어서 흐른다.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(MosaicRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.images.length != widget.images.length) {
      _flow
        ..stop()
        ..duration = _cycleDuration;
      _sync();
    }
  }

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  void _press(int delta) {
    // Listener 는 자기가 down 을 받은 포인터의 up·cancel 만 받는다 — 0 아래로 내려가지 않는다.
    _pointersDown += delta;
    _sync();
  }

  @override
  Widget build(BuildContext context) {
    final cycle = _cycleWidth;
    // 화면 폭을 덮고도 한 벌이 남게 복사한다 — 한 벌만큼 흘러가면 처음 자리로 돌아가도 이음매가 안 보인다.
    final copies = (MediaQuery.sizeOf(context).width / cycle).ceil() + 1;
    return Listener(
      onPointerDown: (_) => _press(1),
      onPointerUp: (_) => _press(-1),
      onPointerCancel: (_) => _press(-1),
      child: UnconstrainedBox(
        constrainedAxis: Axis.vertical,
        alignment: Alignment.centerLeft,
        clipBehavior: Clip.hardEdge,
        child: AnimatedBuilder(
          animation: _flow,
          // 멈춰 있을 때(값 0) 둘째 벌이 x0 에 온다 — pen 과 같은 자리.
          builder: (context, child) => Transform.translate(offset: Offset((_flow.value - 1) * cycle, 0), child: child),
          // 칸 묶음을 한 번 그려 두고 매 프레임 옮기기만 한다 — 경계가 없으면 프레임마다 그림을 다시 그린다.
          child: RepaintBoundary(
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var copy = 0; copy < copies; copy++)
                    for (final image in [...widget.images, null]) ...[
                      // 화면 읽기는 멈춰 있을 때 x0 에 오는 둘째 벌만 읽는다 — 복사본까지 읽으면 같은 말을 되풀이한다.
                      ExcludeSemantics(
                        excluding: copy != 1,
                        child: image == null ? const MosaicEmptyTile() : MosaicPersonTile(image: image),
                      ),
                      const SizedBox(width: _gap),
                    ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
