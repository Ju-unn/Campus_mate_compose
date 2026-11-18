import 'dart:math' as math;

import 'package:campus_mate_admin/charts/chart_frame.dart';
import 'package:campus_mate_admin/charts/chart_parts.dart';
import 'package:campus_mate_admin/charts/chart_scale.dart';
import 'package:campus_mate_admin/server_status/server_status_models.dart' show formatKstTime;
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:flutter/material.dart';

/// 5분 칸 막대 그래프(pen A11 요청 수 myv3O · 서버 오류 UjrOs, 520×240): 왼쪽 44 · 오른쪽 16 안의 칸마다 막대 하나
/// (폭 8 · 위 모서리 2, 칸 가운데), 눈금 [intervals]+1 줄(위 16 · 아래 176, 글자 11), 정각 · 30분 칸 가운데 아래 8 에 "HH:mm"(한국 시간).
/// [threshold] 가 있으면 그 값에 web-danger 1 점선(4/4)을 긋고 범례는 점선 "[thresholdLabel]" 하나(위 205), 없으면 범례 없음.
/// 마우스를 올린 칸에는 #00000010 띠와 말풍선("HH:mm" · 이름 값) — 묶음 막대(GroupedBarChart)와 같다.
class TimeBarChart extends StatelessWidget {
  const TimeBarChart({
    super.key,
    required this.name,
    required this.times,
    required this.series,
    required this.summary,
    required this.intervals,
    this.threshold,
    this.thresholdLabel,
  });

  static const double height = 240;
  static const double top = 16;
  static const double base = 176;
  static const double leftPad = 44;
  static const double rightPad = 16;
  static const double barWidth = 8;

  final String name;

  /// 칸 시작 시각(오래된 순)
  final List<DateTime> times;
  final ChartSeries series;
  final String summary;
  final int intervals;
  final int? threshold;
  final String? thresholdLabel;

  @override
  Widget build(BuildContext context) {
    if (times.isEmpty) return const SizedBox(height: height);
    final threshold = this.threshold;
    final scale = chartScale(math.max(series.values.fold<int>(0, math.max), threshold ?? 0), intervals: intervals);
    double slotOf(double width) => (width - leftPad - rightPad) / times.length;
    return ChartFrame(
      name: name,
      summary: summary,
      height: height,
      series: [series],
      legendLeft: leftPad,
      legendTop: 205,
      legend: threshold == null ? const SizedBox.shrink() : _ThresholdLegend(label: thresholdLabel ?? '$threshold'),
      painterBuilder: (width, hover) =>
          _TimeBarPainter(series: series, scale: scale, slot: slotOf(width), count: times.length, hover: hover, threshold: threshold),
      labelsBuilder: (width) => [
        for (final (i, tick) in scale.ticks.indexed)
          chartLabel('$tick', left: leftPad - 6 - 80, top: base - (base - top) * i / intervals - 8, align: TextAlign.right, style: chartTextStyle(size: 11)),
        for (final (i, at) in times.indexed)
          if (at.toUtc().minute % 30 == 0)
            chartLabel(formatKstTime(at), left: leftPad + slotOf(width) * (i + 0.5) - 40, top: base + 8, style: chartTextStyle(size: 11)),
      ],
      hitTest: (position, width) {
        final x = position.dx - leftPad;
        if (position.dy > base || x < 0 || x >= slotOf(width) * times.length) return null;
        return (x / slotOf(width)).floor();
      },
      tipBuilder: (index, width) {
        final slot = slotOf(width);
        return ChartTip(
          title: formatKstTime(times[index]),
          rows: [(series, series.values[index])],
          anchor: Rect.fromLTWH(leftPad + slot * index, top, slot, base - top),
          top: 9,
        );
      },
    );
  }
}

/// 점선 한 줄: 길이 [width], 4 긋고 4 띄운다
void _dashedLine(Canvas canvas, Offset start, double width, Paint paint) {
  for (var x = 0.0; x < width; x += 8) {
    canvas.drawLine(start.translate(x, 0), start.translate(math.min(x + 4, width), 0), paint);
  }
}

final Paint _thresholdPaint = Paint()
  ..color = AdminColors.danger
  ..strokeWidth = 1;

/// pen Legend · 이상 기준(sH8yB): 점선 14×2 → 6 → 글자 12 chart-axis
class _ThresholdLegend extends StatelessWidget {
  const _ThresholdLegend({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 14, height: 2, child: CustomPaint(painter: _LegendDashPainter())),
        const SizedBox(width: 6),
        Text(label, maxLines: 1, softWrap: false, style: chartTextStyle()),
      ],
    );
  }
}

class _LegendDashPainter extends CustomPainter {
  const _LegendDashPainter();

  @override
  void paint(Canvas canvas, Size size) => _dashedLine(canvas, Offset(0, size.height / 2), size.width, _thresholdPaint);

  @override
  bool shouldRepaint(_LegendDashPainter old) => false;
}

class _TimeBarPainter extends CustomPainter {
  _TimeBarPainter({required this.series, required this.scale, required this.slot, required this.count, required this.hover, required this.threshold});

  final ChartSeries series;
  final ChartScale scale;
  final double slot;
  final int count;
  final int? hover;
  final int? threshold;

  @override
  void paint(Canvas canvas, Size size) {
    const top = TimeBarChart.top;
    const base = TimeBarChart.base;
    const left = TimeBarChart.leftPad;
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
    final bar = Paint()..color = series.color;
    for (var i = 0; i < count; i++) {
      final value = series.values[i];
      if (value <= 0) continue;
      final barHeight = math.max(1.0, (base - top) * math.min(value, scale.max) / scale.max);
      final x = left + slot * i + (slot - TimeBarChart.barWidth) / 2;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x, base - barHeight, TimeBarChart.barWidth, barHeight),
          topLeft: const Radius.circular(2),
          topRight: const Radius.circular(2),
        ),
        bar,
      );
    }
    final line = threshold;
    if (line != null) _dashedLine(canvas, Offset(left, base - (base - top) * line / scale.max), right - left, _thresholdPaint);
  }

  @override
  bool shouldRepaint(_TimeBarPainter old) => true;
}
