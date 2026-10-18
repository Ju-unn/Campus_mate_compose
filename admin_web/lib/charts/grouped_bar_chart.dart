import 'dart:math' as math;

import 'package:campus_mate_admin/billing/billing_item.dart' show formatMonthDay;
import 'package:campus_mate_admin/charts/chart_frame.dart';
import 'package:campus_mate_admin/charts/chart_parts.dart';
import 'package:campus_mate_admin/charts/chart_scale.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:flutter/material.dart';

/// 묶음 막대 그래프(pen A2 접수량 Bar N26OY, 520×240): 날마다 줄 수만큼 막대(폭 10 · 사이 2 · 위 모서리 2)를 칸 가운데에 묶어 세우고,
/// 눈금 [intervals]+1 줄(위 17 · 아래 177), 날짜 4개(칸 가운데 · 아래 8), 범례(위 212). 마우스를 올린 칸에는 #00000010 띠.
class GroupedBarChart extends StatelessWidget {
  const GroupedBarChart({
    super.key,
    required this.name,
    required this.dates,
    required this.series,
    required this.summary,
    required this.intervals,
    required this.leftPad,
    required this.rightPad,
    required this.legendLeft,
  });

  static const double height = 240;
  static const double top = 17;
  static const double base = 177;
  static const double plotArea = 200;
  static const double barWidth = 10;
  static const double barGap = 2;

  final String name;
  final List<String> dates;
  final List<ChartSeries> series;
  final String summary;
  final int intervals;
  final double leftPad;
  final double rightPad;
  final double legendLeft;

  @override
  Widget build(BuildContext context) {
    if (dates.isEmpty) return const SizedBox(height: height);
    final peak = series.expand((line) => line.values).fold<int>(0, math.max);
    final scale = chartScale(peak, intervals: intervals);
    double slotOf(double width) => (width - leftPad - rightPad) / dates.length;
    return ChartFrame(
      name: name,
      summary: summary,
      height: height,
      series: series,
      legendLeft: legendLeft,
      legendTop: 212,
      painterBuilder: (width, hover) => _BarPainter(series: series, scale: scale, left: leftPad, slot: slotOf(width), count: dates.length, hover: hover),
      labelsBuilder: (width) => [
        for (final (i, tick) in scale.ticks.indexed)
          chartLabel('$tick', left: leftPad - 6 - 80, top: base - (base - top) * i / intervals - 8, align: TextAlign.right),
        for (final i in dateLabelIndexes(dates.length, 4))
          chartLabel(formatMonthDay(dates[i]), left: leftPad + slotOf(width) * i + slotOf(width) / 2 - 40, top: base + 8),
      ],
      hitTest: (position, width) {
        final x = position.dx - leftPad;
        if (position.dy > plotArea || x < 0 || x >= slotOf(width) * dates.length) return null;
        return (x / slotOf(width)).floor();
      },
      tipBuilder: (index, width) {
        final slot = slotOf(width);
        return ChartTip(
          title: dayWithWeekday(dates[index]),
          rows: [for (final line in series) (line, line.values[index])],
          anchor: Rect.fromLTWH(leftPad + slot * index, top, slot, base - top),
          top: 9,
        );
      },
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({required this.series, required this.scale, required this.left, required this.slot, required this.count, required this.hover});

  final List<ChartSeries> series;
  final ChartScale scale;
  final double left;
  final double slot;
  final int count;
  final int? hover;

  @override
  void paint(Canvas canvas, Size size) {
    const top = GroupedBarChart.top;
    const base = GroupedBarChart.base;
    final right = left + slot * count;
    final grid = Paint()
      ..color = AdminColors.chartGrid
      ..strokeWidth = 1;
    for (var i = 0; i <= scale.intervals; i++) {
      final y = base - (base - top) * i / scale.intervals;
      canvas.drawLine(Offset(left, y), Offset(right, y), grid);
    }
    final hovered = hover;
    if (hovered != null) {
      canvas.drawRect(Rect.fromLTWH(left + slot * hovered, top, slot, base - top), Paint()..color = const Color(0x10000000));
    }
    final groupWidth = series.length * GroupedBarChart.barWidth + (series.length - 1) * GroupedBarChart.barGap;
    for (var i = 0; i < count; i++) {
      for (final (s, line) in series.indexed) {
        final value = line.values[i];
        if (value <= 0) continue;
        final barHeight = math.max(1.0, (base - top) * math.min(value, scale.max) / scale.max);
        final x = left + slot * i + (slot - groupWidth) / 2 + s * (GroupedBarChart.barWidth + GroupedBarChart.barGap);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(x, base - barHeight, GroupedBarChart.barWidth, barHeight),
            topLeft: const Radius.circular(2),
            topRight: const Radius.circular(2),
          ),
          Paint()..color = line.color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) => true;
}
