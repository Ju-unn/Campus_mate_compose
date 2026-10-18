import 'package:campus_mate_admin/billing/revenue_chart.dart' show niceTickStep;
import 'package:campus_mate_admin/charts/chart_scale.dart';
import 'package:flutter_test/flutter_test.dart';

/// 그래프 공용 눈금(대장 결정 2: y 최댓값은 데이터에 맞춘 깔끔한 눈금, 최소 4) · 날짜 글자
void main() {
  group('chartScale — 1 · 2 · 5 × 10^k 칸 크기', () {
    test('pen A2 가입 추이: 최댓값 47 · 눈금 4줄(칸 3) → 0 · 20 · 40 · 60', () {
      final scale = chartScale(47, intervals: 3);
      expect((scale.step, scale.max), (20, 60));
      expect(scale.ticks, [0, 20, 40, 60]);
    });

    test('pen A9 추이: 최댓값 31 · 눈금 5줄(칸 4) → 0 · 10 · 20 · 30 · 40', () {
      expect(chartScale(31, intervals: 4).ticks, [0, 10, 20, 30, 40]);
    });

    test('pen A2 학교별 막대: 최댓값 62 · 눈금 5줄 → 0 · 20 · 40 · 60 · 80', () {
      expect(chartScale(62, intervals: 4).ticks, [0, 20, 40, 60, 80]);
    });

    test('접수량 막대: 눈금 3줄(칸 2) — 최댓값 15 → 0 · 10 · 20', () {
      expect(chartScale(15, intervals: 2).ticks, [0, 10, 20]);
    });

    test('데이터가 없거나 작아도 맨 위 눈금은 최소 4', () {
      expect(chartScale(0, intervals: 2).ticks, [0, 2, 4]);
      expect(chartScale(0, intervals: 3).ticks, [0, 2, 4, 6]);
      expect(chartScale(0, intervals: 4).ticks, [0, 1, 2, 3, 4]);
      expect(chartScale(3, intervals: 4).max, 4);
    });

    test('눈금 위에 딱 걸린 최댓값은 그 눈금에 둔다(넘지 않는다)', () {
      expect(chartScale(60, intervals: 3).max, 60);
      expect(chartScale(61, intervals: 3).max, 150); // 칸 21 → 다음 후보 50
    });

    test('매출 그래프(W3)의 칸 크기는 같은 함수에서 나온다 — 값은 그대로', () {
      expect(niceTickStep(285000), 100000);
      expect(niceTickStep(300001), 200000);
      expect(niceTickStep(0), 100000);
    });
  });

  group('날짜 글자', () {
    test('날짜 칸 위치: 30일 5개 → 처음 · 7 · 14 · 21 · 마지막(pen 9/19 · 9/26 · 10/3 · 10/10 · 10/18)', () {
      expect(dateLabelIndexes(30, 5), [0, 7, 14, 21, 29]);
    });

    test('날짜 칸 위치: 14일 4개 → 0 · 4 · 8 · 13(pen 10/5 · 10/9 · 10/13 · 10/18)', () {
      expect(dateLabelIndexes(14, 4), [0, 4, 8, 13]);
    });

    test('하루뿐이면 한 칸', () {
      expect(dateLabelIndexes(1, 5), [0]);
    });

    test('말풍선 제목은 "M/D (요일)" — 한국 날짜 그대로 요일만 붙인다', () {
      expect(dayWithWeekday('2026-10-14'), '10/14 (수)');
      expect(dayWithWeekday('2026-10-18'), '10/18 (일)');
      expect(dayWithWeekday('2026-10-19'), '10/19 (월)');
    });

    test('모양이 다른 글자는 그대로', () {
      expect(dayWithWeekday('어제'), '어제');
    });
  });

  group('가장 많은 날(화면 읽기용)', () {
    test('여러 줄의 합이 가장 큰 칸, 같으면 더 최근', () {
      expect(peakIndex([[1, 5, 2], [1, 0, 9]]), 2);
      expect(peakIndex([[3, 3, 1]]), 1);
    });
  });
}
