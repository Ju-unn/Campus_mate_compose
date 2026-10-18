import 'dart:math' as math;

import 'package:campus_mate_admin/billing/billing_item.dart' show formatMonthDay;

/// 그래프 세로 눈금: 칸 [intervals] 개 × 칸 크기 [step]. 눈금 글자는 [ticks](0 부터).
class ChartScale {
  const ChartScale(this.step, this.intervals);

  final int step;
  final int intervals;

  /// 맨 위 눈금
  int get max => step * intervals;

  List<int> get ticks => [for (var i = 0; i <= intervals; i++) step * i];
}

/// 칸 크기 = 1 · 2 · 5 × 10^k 중 [peak] 를 칸 [intervals] 개로 덮는 가장 작은 값. 맨 위 눈금은 최소 [minMax](대장 결정 2: 최소 4),
/// 칸은 [minStep] 보다 작지 않다(매출 그래프의 1,000 원).
int niceStep(int peak, {required int intervals, int minMax = 4, int minStep = 1}) {
  final need = math.max(math.max((peak / intervals).ceil(), (minMax / intervals).ceil()), minStep);
  for (var unit = 1;; unit *= 10) {
    for (final m in const [1, 2, 5]) {
      if (m * unit >= need) return m * unit;
    }
  }
}

ChartScale chartScale(int peak, {required int intervals, int minMax = 4}) {
  return ChartScale(niceStep(peak, intervals: intervals, minMax: minMax), intervals);
}

/// 가로 눈금 날짜를 붙일 칸 번호: 처음 · 마지막 · 그 사이를 고르게(30일 5개 → 0 · 7 · 14 · 21 · 29, 14일 4개 → 0 · 4 · 8 · 13)
List<int> dateLabelIndexes(int count, int labels) {
  if (count <= 0) return const [];
  if (count == 1 || labels <= 1) return const [0];
  return {for (var k = 0; k < labels; k++) (count - 1) * k ~/ (labels - 1)}.toList();
}

/// 말풍선 제목 "10/14 (수)" — 서버 한국 날짜 글자에서 요일만 계산한다(시간대 계산 없음). 모양이 다르면 그대로.
String dayWithWeekday(String date) {
  final parts = date.split('-').map(int.tryParse).toList();
  if (parts.length != 3 || parts.contains(null)) return date;
  final weekday = DateTime.utc(parts[0]!, parts[1]!, parts[2]!).weekday; // 1 = 월
  return '${formatMonthDay(date)} (${'월화수목금토일'[weekday - 1]})';
}

/// 여러 줄의 합이 가장 큰 칸 번호(같으면 더 최근). 화면 읽기 요약의 "가장 많은 날".
int peakIndex(List<List<int>> series) {
  var best = 0;
  var bestSum = -1;
  for (var i = 0; i < series.first.length; i++) {
    final sum = series.fold<int>(0, (total, line) => total + line[i]);
    if (sum >= bestSum) {
      best = i;
      bestSum = sum;
    }
  }
  return best;
}
