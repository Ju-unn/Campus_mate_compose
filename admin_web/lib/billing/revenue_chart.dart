import 'dart:math' as math;

import 'package:campus_mate_admin/billing/billing_item.dart';
import 'package:campus_mate_admin/charts/chart_scale.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:flutter/material.dart';

/// 그래프 세로 눈금 한 칸의 크기: 눈금 3칸이 가장 큰 날을 덮는 1 · 2 · 5 × 10^k (최소 1,000). 매출이 모두 0 이면 10만(pen 0 · 10만 · 20만 · 30만).
/// 계산은 홈 · 매칭 그래프와 같은 [niceStep] 이다.
int niceTickStep(int maxValue) {
  if (maxValue <= 0) return 100000;
  return niceStep(maxValue, intervals: 3, minMax: 0, minStep: 1000);
}

/// 눈금 글자: 0 · 5천 · 10만 · 1.5만
String tickLabel(int value) {
  if (value == 0) return '0';
  if (value >= 10000) return value % 10000 == 0 ? '${value ~/ 10000}만' : '${(value / 10000).toStringAsFixed(1)}만';
  if (value >= 1000 && value % 1000 == 0) return '${value ~/ 1000}천';
  return '$value';
}

/// 화면 읽기용 한 줄(대장 결정 9): "최근 30일 매출 합계 ₩n, 가장 많은 날 M/D ₩n". 매출이 없으면 합계만.
String revenueSummaryLabel(List<DailyRevenue> days) {
  final total = days.fold<int>(0, (sum, d) => sum + d.revenueKrw);
  final head = '최근 ${days.length}일 매출 합계 ${formatWon(total)}';
  if (total == 0) return head;
  var best = days.first;
  for (final day in days) {
    if (day.revenueKrw >= best.revenueKrw) best = day; // 같은 금액이면 더 최근 날
  }
  return '$head, 가장 많은 날 ${formatMonthDay(best.date)} ${formatWon(best.revenueKrw)}';
}

/// pen Chart·Bar(Revenue)(H8E2sn · A8 PNG 측정): 폭 1080(좁은 창은 줄어든다) · 높이 240 — 세로 눈금 4줄(0 · 10만 · 20만 · 30만, 최댓값은 데이터에
/// 맞춘다) · 막대 일 30개 chart-revenue(위 모서리 2) · 가로 눈금 날짜 5개 · 아래 범례. 새 부품 없이 직접 그린다(대장 결정 9).
/// 마우스를 올리면 그날 "M/D · ₩n" 말풍선. 값은 서버 날짜 글자 그대로. 그림 전체는 화면 읽기에서 한 줄로 읽힌다.
class RevenueChart extends StatefulWidget {
  const RevenueChart({super.key, required this.days});

  static const double maxWidth = 1080;
  static const double height = 240;

  /// 그림(눈금 · 막대 · 날짜) 높이 — 아래 12 + 범례 16 + 12 가 이어서 240
  static const double plotAreaHeight = 200;
  static const double axisWidth = 57;
  static const double rightPad = 24;
  static const double top = 17;
  static const double base = 177;

  final List<DailyRevenue> days;

  @override
  State<RevenueChart> createState() => _RevenueChartState();
}

class _RevenueChartState extends State<RevenueChart> {
  int? _hover;

  void _onHover(PointerEvent event, double width) {
    final days = widget.days;
    if (days.isEmpty) return;
    final slot = (width - RevenueChart.axisWidth - RevenueChart.rightPad) / days.length;
    final x = event.localPosition.dx - RevenueChart.axisWidth;
    final inPlot = x >= 0 && x < slot * days.length && event.localPosition.dy <= RevenueChart.plotAreaHeight;
    final index = inPlot ? (x / slot).floor() : null;
    if (index != _hover) setState(() => _hover = index);
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    if (days.isEmpty) return const SizedBox(height: RevenueChart.height);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(constraints.maxWidth, RevenueChart.maxWidth);
        final peak = days.fold<int>(0, (m, d) => math.max(m, d.revenueKrw));
        final step = niceTickStep(peak);
        final axisMax = step * 3;
        final slot = (width - RevenueChart.axisWidth - RevenueChart.rightPad) / days.length;
        final hover = _hover;
        Widget? tooltip;
        if (hover != null && hover < days.length) {
          final day = days[hover];
          final barTop = RevenueChart.base - (RevenueChart.base - RevenueChart.top) * day.revenueKrw / axisMax;
          tooltip = Positioned(
            left: RevenueChart.axisWidth + slot * hover + slot / 2,
            top: math.max(0, barTop - 8 - 28),
            child: FractionalTranslation(
              translation: const Offset(-0.5, 0),
              child: Container(
                key: const ValueKey('chart-tooltip'),
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: AdminSpacing.sm),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AdminColors.ink, borderRadius: BorderRadius.circular(AdminRadius.sm)),
                child: Text(
                  '${formatMonthDay(day.date)} · ${formatWon(day.revenueKrw)}',
                  style: AdminTypography.xsStrong.copyWith(color: AdminColors.onPrimary),
                ),
              ),
            ),
          );
        }
        return Align(
          alignment: Alignment.centerLeft,
          child: Semantics(
            container: true,
            label: revenueSummaryLabel(days),
            excludeSemantics: true,
            child: SizedBox(
              key: const ValueKey('revenue-chart'),
              width: width,
              height: RevenueChart.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    width: width,
                    height: RevenueChart.plotAreaHeight,
                    child: MouseRegion(
                      onHover: (event) => _onHover(event, width),
                      onExit: (_) => setState(() => _hover = null),
                      child: CustomPaint(painter: _ChartPainter(days: days, step: step)),
                    ),
                  ),
                  // 범례: 막대 색 네모 10 → 6 → 글자 12 web-muted. 눈금 글자 칸 오른쪽(가로선 시작)에 맞춘다.
                  Positioned(
                    left: RevenueChart.axisWidth - 1,
                    top: 212,
                    height: 16,
                    child: Row(
                      children: [
                        Container(
                          key: const ValueKey('chart-legend-swatch'),
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: AdminColors.chartRevenue, borderRadius: BorderRadius.circular(2)),
                        ),
                        const SizedBox(width: 6),
                        Text('일 매출 (원, 시험 결제 제외)', style: AdminTypography.xs.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted)),
                      ],
                    ),
                  ),
                  ?tooltip,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({required this.days, required this.step});

  final List<DailyRevenue> days;
  final int step;

  static const int _ticks = 4;

  TextPainter _text(String text) {
    return TextPainter(
      text: TextSpan(text: text, style: AdminTypography.xs.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
  }

  @override
  void paint(Canvas canvas, Size size) {
    const left = RevenueChart.axisWidth;
    final right = size.width - RevenueChart.rightPad;
    const top = RevenueChart.top;
    const base = RevenueChart.base;
    final plotHeight = base - top;
    final axisMax = step * (_ticks - 1);
    final line = Paint()
      ..color = AdminColors.hairline
      ..strokeWidth = 1;
    for (var i = 0; i < _ticks; i++) {
      final y = base - plotHeight * i / (_ticks - 1);
      canvas.drawLine(Offset(left, y), Offset(right, y), line);
      final label = _text(tickLabel(step * i));
      label.paint(canvas, Offset(left - 7 - label.width, y - label.height / 2));
    }
    final slot = (right - left) / days.length;
    final barWidth = slot * 0.66;
    for (final (i, day) in days.indexed) {
      final height = day.revenueKrw <= 0 ? 0.0 : math.max(1.0, plotHeight * day.revenueKrw / axisMax);
      if (height == 0) continue;
      final x = left + slot * i + (slot - barWidth) / 2;
      final rect = Rect.fromLTWH(x, base - height, barWidth, height);
      canvas.drawRRect(
        RRect.fromRectAndCorners(rect, topLeft: const Radius.circular(2), topRight: const Radius.circular(2)),
        Paint()..color = AdminColors.chartRevenue,
      );
    }
    // 날짜 5개(첫날 · 4분의 1 지점들 · 마지막 날), 막대 가운데에 맞춘다
    final last = days.length - 1;
    for (var k = 0; k < 5; k++) {
      final i = (last * k / 4).floor();
      final label = _text(formatMonthDay(days[i].date));
      final center = left + slot * i + slot / 2;
      label.paint(canvas, Offset((center - label.width / 2).clamp(0, size.width - label.width), base + 8));
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) => old.days != days || old.step != step;
}
