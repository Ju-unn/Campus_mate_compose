import 'dart:math' as math;

import 'package:campus_mate_admin/charts/chart_parts.dart';
import 'package:flutter/material.dart';

/// 올린 칸(날짜 · 학교)의 말풍선 내용과 놓을 자리. [anchor] 는 그림 안 좌표, 말풍선은 그 오른쪽 8(pen)에 [top] 높이로 놓고,
/// 그림 오른쪽 끝을 넘을 만하면(말풍선 폭을 100 으로 어림) 왼쪽 8 로 뒤집는다.
class ChartTip {
  const ChartTip({required this.title, required this.rows, required this.anchor, required this.top});

  final String title;
  final List<(ChartSeries, int)> rows;
  final Rect anchor;
  final double top;
}

/// 세 그래프(선 · 묶음 막대 · 가로 막대)가 같이 쓰는 틀: 폭 정하기 · 마우스 올림 · 말풍선 · 범례 · 화면 읽기 요약.
/// 그림 자체(격자 · 선 · 막대)는 [painterBuilder], 눈금 · 날짜 글자는 [labelsBuilder](Positioned 글자들)가 맡는다.
/// 움직임은 없다 — 읽는 데이터가 스타일 때문에 움직이지 않게(말풍선도 바로 뜨고 바로 사라진다).
class ChartFrame extends StatefulWidget {
  const ChartFrame({
    super.key,
    required this.name,
    required this.summary,
    required this.height,
    required this.series,
    required this.legendLeft,
    required this.legendTop,
    required this.painterBuilder,
    required this.labelsBuilder,
    required this.hitTest,
    required this.tipBuilder,
    this.maxWidth,
  });

  /// 키 이름: `chart-$name`(그림 상자) · `chart-$name-plot`(CustomPaint) · `chart-$name-tooltip` · `chart-$name-legend-N`
  final String name;

  /// 화면 읽기가 그림 대신 읽는 한 줄(합계 · 가장 많은 날)
  final String summary;
  final double height;
  final double? maxWidth;
  final List<ChartSeries> series;
  final double legendLeft;
  final double legendTop;
  final CustomPainter Function(double width, int? hover) painterBuilder;
  final List<Widget> Function(double width) labelsBuilder;

  /// 마우스 위치(그림 안 좌표)가 가리키는 칸 번호, 없으면 null
  final int? Function(Offset position, double width) hitTest;
  final ChartTip? Function(int index, double width) tipBuilder;

  @override
  State<ChartFrame> createState() => _ChartFrameState();
}

class _ChartFrameState extends State<ChartFrame> {
  /// 말풍선이 오른쪽에 들어가는지 볼 때 쓰는 어림 폭(pen 88, 이름이 긴 줄은 더 넓다)
  static const double _tipRoom = 100;

  int? _hover;

  void _setHover(int? index) {
    if (index != _hover) setState(() => _hover = index);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(constraints.maxWidth, widget.maxWidth ?? double.infinity);
        final hover = _hover;
        final tip = hover == null ? null : widget.tipBuilder(hover, width);
        return Align(
          alignment: Alignment.centerLeft,
          child: Semantics(
            container: true,
            label: widget.summary,
            excludeSemantics: true,
            child: SizedBox(
              key: ValueKey('chart-${widget.name}'),
              width: width,
              height: widget.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: MouseRegion(
                      onHover: (event) => _setHover(widget.hitTest(event.localPosition, width)),
                      onExit: (_) => _setHover(null),
                      child: CustomPaint(key: ValueKey('chart-${widget.name}-plot'), painter: widget.painterBuilder(width, hover)),
                    ),
                  ),
                  ...widget.labelsBuilder(width),
                  Positioned(left: widget.legendLeft, top: widget.legendTop, height: 16, child: ChartLegend(name: widget.name, series: widget.series)),
                  if (tip != null) _tooltip(tip, width),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tooltip(ChartTip tip, double width) {
    final onRight = tip.anchor.right + 8 + _tipRoom <= width;
    return Positioned(
      left: onRight ? tip.anchor.right + 8 : null,
      right: onRight ? null : width - tip.anchor.left + 8,
      top: tip.top,
      // 말풍선이 마우스를 가로채면 올림이 풀려 깜빡인다
      child: IgnorePointer(
        child: ChartTooltipBox(boxKey: ValueKey('chart-${widget.name}-tooltip'), title: tip.title, rows: tip.rows),
      ),
    );
  }
}
