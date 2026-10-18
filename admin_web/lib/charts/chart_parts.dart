import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:flutter/material.dart';

/// 줄 구분을 색 말고 모양으로도 한다(pen: 원 · 사각 · 삼각).
enum ChartMarker { circle, square, triangle }

/// 그래프의 한 줄(선 · 막대 한 종류). [values] 는 칸(날짜 · 학교)마다 하나.
class ChartSeries {
  const ChartSeries({required this.name, required this.color, required this.marker, required this.values});

  final String name;
  final Color color;
  final ChartMarker marker;
  final List<int> values;
}

/// 표시 하나를 [center] 에 그린다. 원 · 사각(모서리 2) 은 한 변 [size], 삼각은 밑변 · 높이 [size].
void paintChartMarker(Canvas canvas, ChartMarker marker, Offset center, double size, Color color) {
  final paint = Paint()..color = color;
  switch (marker) {
    case ChartMarker.circle:
      canvas.drawCircle(center, size / 2, paint);
    case ChartMarker.square:
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: center, width: size, height: size), const Radius.circular(2)), paint);
    case ChartMarker.triangle:
      final half = size / 2;
      canvas.drawPath(
        Path()
          ..moveTo(center.dx, center.dy - half)
          ..lineTo(center.dx + half, center.dy + half)
          ..lineTo(center.dx - half, center.dy + half)
          ..close(),
        paint,
      );
  }
}

/// 범례 · 말풍선 줄 앞의 표시(그림 안의 끝 표시와 같은 모양)
class ChartMarkerBox extends StatelessWidget {
  const ChartMarkerBox({super.key, required this.marker, required this.color, required this.size});

  final ChartMarker marker;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MarkerPainter(marker, color, size)),
    );
  }
}

class _MarkerPainter extends CustomPainter {
  const _MarkerPainter(this.marker, this.color, this.size);

  final ChartMarker marker;
  final Color color;
  final double size;

  @override
  void paint(Canvas canvas, Size box) => paintChartMarker(canvas, marker, box.center(Offset.zero), size, color);

  @override
  bool shouldRepaint(_MarkerPainter old) => old.marker != marker || old.color != color || old.size != size;
}

/// 글자 [size] 의 줄 상자가 16 이 되는 그래프 글자(눈금 · 날짜 · 범례 12, 막대 끝 숫자 11)
TextStyle chartTextStyle({double size = 12, FontWeight? weight, Color color = AdminColors.chartAxis}) {
  return AdminTypography.xs.copyWith(fontSize: size, fontWeight: weight, height: 16 / size, color: color);
}

/// 그림 안에 놓는 글자 한 줄: 폭 [width] 상자의 왼쪽 [left] · 위 [top], 줄 높이 16. 가운데 · 오른쪽 맞춤은 상자 안에서 한다.
/// 화면 읽기에는 그림 전체 요약이 대신 읽히므로 이 글자들은 읽히지 않는다(ChartFrame 의 Semantics).
Widget chartLabel(
  String text, {
  required double left,
  required double top,
  double width = 80,
  TextAlign align = TextAlign.center,
  TextStyle? style,
  bool ellipsis = false,
}) {
  return Positioned(
    left: left,
    top: top,
    width: width,
    height: 16,
    child: Text(
      text,
      textAlign: align,
      maxLines: 1,
      softWrap: false,
      overflow: ellipsis ? TextOverflow.ellipsis : TextOverflow.clip,
      style: style ?? chartTextStyle(),
    ),
  );
}

/// 범례: 표시(10, 삼각은 12) → 4 → 글자 12 chart-axis, 줄 사이 24(pen A2 · A9 PNG 측정)
class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.name, required this.series});

  final String name;
  final List<ChartSeries> series;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, line) in series.indexed) ...[
          if (i > 0) const SizedBox(width: AdminSpacing.lg),
          ChartMarkerBox(
            key: ValueKey('chart-$name-legend-$i'),
            marker: line.marker,
            color: line.color,
            size: line.marker == ChartMarker.triangle ? 12 : 10,
          ),
          const SizedBox(width: AdminSpacing.xxs),
          Text(line.name, maxLines: 1, softWrap: false, style: chartTextStyle()),
        ],
      ],
    );
  }
}

/// pen Tooltip Sbz8p: web-ink 바탕 · 모서리 8 · 안쪽 12 × 8 — 제목 12/700 → (4 간격) 줄마다 [표시 8 → 6 → "이름 값" 12], 글자는 모두 on-primary.
class ChartTooltipBox extends StatelessWidget {
  const ChartTooltipBox({super.key, this.boxKey, required this.title, required this.rows});

  /// 바깥 상자(Container)의 키 — 시험이 바탕 · 크기를 잰다
  final Key? boxKey;
  final String title;
  final List<(ChartSeries, int)> rows;

  /// 제목 16 + 줄마다 4 + 16, 위아래 8 — 말풍선이 그림 밖으로 나가지 않게 놓을 때 쓴다
  static double heightOf(int rowCount) => 32 + 20.0 * rowCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: boxKey,
      padding: const EdgeInsets.symmetric(horizontal: AdminSpacing.sm, vertical: AdminSpacing.xs),
      decoration: BoxDecoration(color: AdminColors.ink, borderRadius: BorderRadius.circular(AdminRadius.sm)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, maxLines: 1, softWrap: false, style: chartTextStyle(weight: FontWeight.w700, color: AdminColors.onPrimary)),
          for (final (line, value) in rows) ...[
            const SizedBox(height: AdminSpacing.xxs),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ChartMarkerBox(marker: line.marker, color: line.color, size: 8),
                const SizedBox(width: 6),
                Text('${line.name} $value', maxLines: 1, softWrap: false, style: chartTextStyle(color: AdminColors.onPrimary)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
