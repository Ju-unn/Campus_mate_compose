import 'dart:math' as math;

import 'package:campus_mate_admin/billing/billing_item.dart' show formatMonthDay;
import 'package:campus_mate_admin/charts/chart_frame.dart';
import 'package:campus_mate_admin/charts/chart_parts.dart';
import 'package:campus_mate_admin/charts/chart_scale.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:flutter/material.dart';

/// 선 그래프(pen A2 가입 추이 Chart Line VzPxr 520×240 · A9 Line(Match) GHCrb 1080×240): 높이 240 — 눈금 선 [intervals]+1 줄(위 17 · 아래 177, chart-grid 1),
/// 날짜 5개(아래 8), 범례(위 212), 선 2.5(chart-* 색), 끝 표시(원 10 · 사각 10 · 삼각 12). 점은 첫날이 왼쪽 눈금 끝, 마지막 날이 오른쪽 끝에 온다.
/// 값이 모두 0 이면 선 · 끝 표시 없이 축과 0 선만. 새 부품 없이 직접 그린다(대장 결정 2).
class AdminLineChart extends StatelessWidget {
  const AdminLineChart({
    super.key,
    required this.name,
    required this.dates,
    required this.series,
    required this.summary,
    required this.intervals,
    required this.leftPad,
    required this.rightPad,
    required this.legendLeft,
    this.maxWidth,
  });

  static const double height = 240;
  static const double top = 17;
  static const double base = 177;

  /// 마우스를 받는 그림 높이(눈금 · 날짜 줄까지, 범례 아래는 뺀다)
  static const double plotArea = 200;
  static const double lineWidth = 2.5;

  final String name;

  /// 서버 한국 날짜 글자(오래된 순) — [series] 값과 같은 칸 수
  final List<String> dates;
  final List<ChartSeries> series;
  final String summary;

  /// 눈금 칸 수(A2 3 → 4줄, A9 4 → 5줄)
  final int intervals;

  /// 왼쪽 눈금 글자 자리 · 오른쪽 여백(pen PNG 측정: A2 42 · 16, A9 54 · 24)
  final double leftPad;
  final double rightPad;
  final double legendLeft;
  final double? maxWidth;

  double _x(int i, double width) {
    final span = width - leftPad - rightPad;
    return dates.length <= 1 ? leftPad : leftPad + span * i / (dates.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    if (dates.isEmpty) return const SizedBox(height: height);
    final peak = series.expand((line) => line.values).fold<int>(0, math.max);
    final scale = chartScale(peak, intervals: intervals);
    return ChartFrame(
      name: name,
      summary: summary,
      height: height,
      maxWidth: maxWidth,
      series: series,
      legendLeft: legendLeft,
      legendTop: 212,
      painterBuilder: (width, hover) => _LinePainter(
        series: series,
        scale: scale,
        left: leftPad,
        right: width - rightPad,
        xOf: (i) => _x(i, width),
        count: dates.length,
        empty: peak == 0,
      ),
      labelsBuilder: (width) => [
        for (final (i, tick) in scale.ticks.indexed)
          chartLabel('$tick', left: leftPad - 6 - 80, top: base - (base - top) * i / intervals - 8, align: TextAlign.right),
        for (final i in dateLabelIndexes(dates.length, 5)) chartLabel(formatMonthDay(dates[i]), left: _x(i, width) - 40, top: base + 8),
      ],
      hitTest: (position, width) {
        if (position.dy > plotArea || position.dx < leftPad - 8 || position.dx > width - rightPad + 8) return null;
        final span = width - leftPad - rightPad;
        return dates.length <= 1 ? 0 : ((position.dx - leftPad) / span * (dates.length - 1)).round().clamp(0, dates.length - 1);
      },
      tipBuilder: (index, width) {
        final x = _x(index, width);
        return ChartTip(
          title: dayWithWeekday(dates[index]),
          rows: [for (final line in series) (line, line.values[index])],
          anchor: Rect.fromLTWH(x - 4, top, 8, base - top),
          top: 9,
        );
      },
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.series,
    required this.scale,
    required this.left,
    required this.right,
    required this.xOf,
    required this.count,
    required this.empty,
  });

  final List<ChartSeries> series;
  final ChartScale scale;
  final double left;
  final double right;
  final double Function(int i) xOf;
  final int count;
  final bool empty;

  double _y(int value) => AdminLineChart.base - (AdminLineChart.base - AdminLineChart.top) * math.min(value, scale.max) / scale.max;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = AdminColors.chartGrid
      ..strokeWidth = 1;
    for (var i = 0; i <= scale.intervals; i++) {
      final y = AdminLineChart.base - (AdminLineChart.base - AdminLineChart.top) * i / scale.intervals;
      canvas.drawLine(Offset(left, y), Offset(right, y), grid);
    }
    if (empty) return;
    for (final line in series) {
      final path = Path();
      for (var i = 0; i < count; i++) {
        final point = Offset(xOf(i), _y(line.values[i]));
        i == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = line.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = AdminLineChart.lineWidth
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
    // 끝 표시는 선 위에(마지막 날)
    for (final line in series) {
      final size = line.marker == ChartMarker.triangle ? 12.0 : 10.0;
      paintChartMarker(canvas, line.marker, Offset(xOf(count - 1), _y(line.values[count - 1])), size, line.color);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => true; // 호출한 쪽이 데이터를 바꿀 때만 다시 만든다(그림이 가볍다)
}
