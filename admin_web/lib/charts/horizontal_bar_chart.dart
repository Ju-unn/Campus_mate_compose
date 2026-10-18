import 'dart:math' as math;

import 'package:campus_mate_admin/charts/chart_frame.dart';
import 'package:campus_mate_admin/charts/chart_parts.dart';
import 'package:campus_mate_admin/charts/chart_scale.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:flutter/material.dart';

/// 가로 막대 그래프(pen A2 학교별 활성 HBar trqni, 학교 5곳일 때 520×240): 학교마다 줄 수만큼 막대(높이 13 · 사이 1 · 오른쪽 모서리 3)를
/// 묶어 세우고(학교 사이 34, 맨 위 12), 왼쪽 90 은 학교 이름(12 ink), 막대 끝에 숫자(11 chart-axis),
/// 세로 눈금 5줄(칸 4 · 데이터에 맞춤)과 그 글자는 막대 아래 6, 범례는 그 아래 10. 높이 = 34 × 학교 수 + 70.
class HorizontalBarChart extends StatelessWidget {
  const HorizontalBarChart({
    super.key,
    required this.name,
    required this.labels,
    required this.titles,
    required this.series,
    required this.summary,
  });

  static const double rowPitch = 34;
  static const double firstRow = 12;
  static const double barHeight = 13;
  static const double barGap = 1;
  static const double plotLeft = 90;
  static const double rightPad = 49;
  static const int intervals = 4;

  /// 그림 높이 = 학교 34 × 수 + 70(5곳이면 240)
  static double heightFor(int rows) => rowPitch * rows + 70;

  final String name;

  /// 막대 왼쪽 학교 이름(줄인 것)
  final List<String> labels;

  /// 말풍선 제목(학교 전체 이름)
  final List<String> titles;

  /// 줄마다 학교 수만큼의 값(남 · 여)
  final List<ChartSeries> series;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final rows = labels.length;
    if (rows == 0) return const SizedBox(height: 240);
    final peak = series.expand((line) => line.values).fold<int>(0, math.max);
    final scale = chartScale(peak, intervals: intervals);
    final groupHeight = series.length * barHeight + (series.length - 1) * barGap;
    final bottom = firstRow + rowPitch * rows;
    double plotWidth(double width) => width - plotLeft - rightPad;
    double barWidth(int value, double width) => plotWidth(width) * math.min(value, scale.max) / scale.max;
    return ChartFrame(
      name: name,
      summary: summary,
      height: heightFor(rows),
      series: series,
      legendLeft: plotLeft,
      legendTop: rowPitch * rows + 44,
      painterBuilder: (width, hover) => _HBarPainter(series: series, scale: scale, rows: rows, plotWidth: plotWidth(width)),
      labelsBuilder: (width) => [
        for (final (r, label) in labels.indexed)
          chartLabel(label, left: 0, top: firstRow + rowPitch * r + (groupHeight - 16) / 2, width: plotLeft - 8, align: TextAlign.left, ellipsis: true, style: chartTextStyle(color: AdminColors.ink)),
        for (final (r, _) in labels.indexed)
          for (final (s, line) in series.indexed)
            chartLabel(
              '${line.values[r]}',
              left: plotLeft + barWidth(line.values[r], width) + 6,
              top: firstRow + rowPitch * r + s * (barHeight + barGap) + barHeight / 2 - 8,
              width: 40,
              align: TextAlign.left,
              style: chartTextStyle(size: 11),
            ),
        for (final (i, tick) in scale.ticks.indexed) chartLabel('$tick', left: plotLeft + plotWidth(width) * i / intervals - 40, top: bottom + 6),
      ],
      hitTest: (position, width) {
        final row = ((position.dy - firstRow) / rowPitch).floor();
        return position.dy < firstRow || row >= rows ? null : row;
      },
      tipBuilder: (index, width) {
        final longest = series.map((line) => barWidth(line.values[index], width)).fold<double>(0, math.max);
        // 막대 끝 숫자 오른쪽에 놓되 그림 밖으로 나가지 않게(너무 오른쪽이면 위젯 틀이 왼쪽으로 뒤집는다)
        final x = plotLeft + longest + 30;
        final rowTop = firstRow + rowPitch * index;
        final tipHeight = ChartTooltipBox.heightOf(series.length);
        return ChartTip(
          title: titles[index],
          rows: [for (final line in series) (line, line.values[index])],
          anchor: Rect.fromLTWH(x, rowTop, 0, groupHeight),
          top: (rowTop - 4).clamp(0, math.max(0, heightFor(rows) - tipHeight)).toDouble(),
        );
      },
    );
  }
}

class _HBarPainter extends CustomPainter {
  _HBarPainter({required this.series, required this.scale, required this.rows, required this.plotWidth});

  final List<ChartSeries> series;
  final ChartScale scale;
  final int rows;
  final double plotWidth;

  @override
  void paint(Canvas canvas, Size size) {
    const left = HorizontalBarChart.plotLeft;
    final bottom = HorizontalBarChart.firstRow + HorizontalBarChart.rowPitch * rows;
    final grid = Paint()
      ..color = AdminColors.chartGrid
      ..strokeWidth = 1;
    for (var i = 0; i <= scale.intervals; i++) {
      final x = left + plotWidth * i / scale.intervals;
      canvas.drawLine(Offset(x, 8), Offset(x, bottom), grid);
    }
    for (var r = 0; r < rows; r++) {
      for (final (s, line) in series.indexed) {
        final width = plotWidth * math.min(line.values[r], scale.max) / scale.max;
        if (width <= 0) continue;
        final y = HorizontalBarChart.firstRow + HorizontalBarChart.rowPitch * r + s * (HorizontalBarChart.barHeight + HorizontalBarChart.barGap);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(left, y, width, HorizontalBarChart.barHeight),
            topRight: const Radius.circular(3),
            bottomRight: const Radius.circular(3),
          ),
          Paint()..color = line.color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_HBarPainter old) => true;
}
