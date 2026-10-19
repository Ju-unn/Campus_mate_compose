import 'package:campus_mate_admin/charts/chart_parts.dart';
import 'package:campus_mate_admin/charts/chart_scale.dart';
import 'package:campus_mate_admin/charts/grouped_bar_chart.dart';
import 'package:campus_mate_admin/charts/horizontal_bar_chart.dart';
import 'package:campus_mate_admin/charts/line_chart.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/stats_fakes.dart';

/// 홈 · 매칭 그래프 셋(선 · 묶음 막대 · 가로 막대) — fl_chart 없이 직접 그림(대장 결정 2).
/// pen: A2 가입 추이 cPdMl · 접수량 HWkVo(Sbz8p 말풍선) · 학교별 활성 SIOFd · A9 GHCrb(값표 w4_pen_values).
void main() {
  setUpAll(() async {
    final loader = FontLoader('Pretendard');
    for (final weight in ['Regular', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Pretendard-$weight.otf'));
    }
    await loader.load();
  });

  final days = dailyStatRows();
  final dates = [for (final d in days) d['date']! as String];
  final male = [for (final d in days) d['male_signups']! as int];
  final female = [for (final d in days) d['female_signups']! as int];

  ChartSeries signup(String name, Color color, ChartMarker marker, List<int> values) => ChartSeries(name: name, color: color, marker: marker, values: values);

  Widget signupChart({List<int>? maleValues, List<int>? femaleValues, double? maxWidth}) {
    return AdminLineChart(
      name: 'signups',
      dates: dates,
      series: [
        signup('남 가입', AdminColors.chartMale, ChartMarker.circle, maleValues ?? male),
        signup('여 가입', AdminColors.chartFemale, ChartMarker.square, femaleValues ?? female),
      ],
      summary: '최근 30일 가입 합계',
      intervals: 3,
      leftPad: 42,
      rightPad: 16,
      legendLeft: 44,
      maxWidth: maxWidth,
    );
  }

  final last14 = days.sublist(16);
  final intake = GroupedBarChart(
    name: 'intake',
    dates: [for (final d in last14) d['date']! as String],
    series: [
      signup('신고', AdminColors.chartReport, ChartMarker.square, [for (final d in last14) d['report_count']! as int]),
      signup('인증샷', AdminColors.chartProof, ChartMarker.square, [for (final d in last14) d['proof_count']! as int]),
    ],
    summary: '최근 14일 접수량 합계',
    intervals: 2,
    leftPad: 44,
    rightPad: 16,
    legendLeft: 44,
  );

  HorizontalBarChart schools({int count = 3}) {
    final rows = universityRows().take(count).toList();
    return HorizontalBarChart(
      name: 'schools',
      labels: ['서울대', '연세대', '고려대'].take(count).toList(),
      titles: [for (final r in rows) r['name']! as String],
      series: [
        signup('남 활성', AdminColors.chartMale, ChartMarker.square, [for (final r in rows) r['male_active']! as int]),
        signup('여 활성', AdminColors.chartFemale, ChartMarker.square, [for (final r in rows) r['female_active']! as int]),
      ],
      summary: '학교별 활성 인원',
    );
  }

  Future<void> pump(WidgetTester tester, Widget chart, {double width = 520}) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(alignment: Alignment.topLeft, child: SizedBox(width: width, child: chart)),
        ),
      ),
    );
  }

  Finder key(String name) => find.byKey(ValueKey(name));
  Finder inChart(String chart, Finder what) => find.descendant(of: key('chart-$chart'), matching: what);

  Future<TestGesture> hover(WidgetTester tester, Offset position) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: position);
    await mouse.moveTo(position + const Offset(0, 1));
    await tester.pump();
    return mouse;
  }

  group('선 그래프(A2 가입 추이 · A9 추이)', () {
    testWidgets('A2 520×240 — 눈금 4줄(데이터 최댓값 47 → 0 · 20 · 40 · 60), 날짜 5개', (tester) async {
      await pump(tester, signupChart());

      expect(tester.getSize(key('chart-signups')), const Size(520, 240));
      for (final tick in ['0', '20', '40', '60']) {
        expect(inChart('signups', find.text(tick)), findsOneWidget, reason: tick);
      }
      expect(inChart('signups', find.text('80')), findsNothing);
      for (final date in ['9/19', '9/26', '10/3', '10/10', '10/18']) {
        expect(inChart('signups', find.text(date)), findsOneWidget, reason: date);
      }
    });

    testWidgets('눈금 글자는 12 chart-axis · 날짜는 그림 아래(y 185), 맨 아래 눈금 0 은 y 177 가운데', (tester) async {
      await pump(tester, signupChart());

      final zero = inChart('signups', find.text('0'));
      final style = tester.widget<Text>(zero).style!;
      expect((style.fontSize, style.color), (12, AdminColors.chartAxis));
      final origin = tester.getTopLeft(key('chart-signups'));
      expect(tester.getCenter(zero).dy - origin.dy, closeTo(177, 1));
      expect(tester.getTopLeft(inChart('signups', find.text('9/26'))).dy - origin.dy, closeTo(185, 1));
      // 오른쪽 맞춤: 눈금 글자의 오른쪽 끝이 그림 왼쪽(42)에서 6 떨어진다
      expect(tester.getTopRight(zero).dx - origin.dx, closeTo(36, 1));
    });

    testWidgets('범례: 원 10 · 사각 10 + 글자 12 chart-axis, 그림 아래(y 212) — 모양으로도 구분', (tester) async {
      await pump(tester, signupChart());

      final first = tester.widget<ChartMarkerBox>(key('chart-signups-legend-0'));
      final second = tester.widget<ChartMarkerBox>(key('chart-signups-legend-1'));
      expect((first.marker, first.color, first.size), (ChartMarker.circle, AdminColors.chartMale, 10));
      expect((second.marker, second.color, second.size), (ChartMarker.square, AdminColors.chartFemale, 10));
      final origin = tester.getTopLeft(key('chart-signups'));
      expect(tester.getTopLeft(key('chart-signups-legend-0')) - origin, const Offset(44, 215));
      final label = tester.widget<Text>(inChart('signups', find.text('남 가입')));
      expect((label.style!.fontSize, label.style!.color), (12, AdminColors.chartAxis));
    });

    testWidgets('선 2.5 · 남 chart-male · 여 chart-female, 끝 표시 남 원 · 여 사각', (tester) async {
      await pump(tester, signupChart());

      expect(
        key('chart-signups-plot'),
        paints
          ..path(color: AdminColors.chartMale, strokeWidth: 2.5, style: PaintingStyle.stroke)
          ..path(color: AdminColors.chartFemale, strokeWidth: 2.5, style: PaintingStyle.stroke)
          ..circle(color: AdminColors.chartMale, radius: 5)
          ..rrect(color: AdminColors.chartFemale),
      );
    });

    testWidgets('A9 세 줄(1080×240): 원 · 사각 · 삼각 — 범례도 같은 모양, 눈금 5줄(최댓값 31 → 0 · 10 · 20 · 30 · 40)', (tester) async {
      final rows = matchDailyRows();
      await pump(
        tester,
        AdminLineChart(
          name: 'matching',
          dates: [for (final r in rows) r['date']! as String],
          series: [
            signup('수락', AdminColors.chartAccept, ChartMarker.circle, [for (final r in rows) r['accept_count']! as int]),
            signup('매칭', AdminColors.chartMatch, ChartMarker.square, [for (final r in rows) r['match_count']! as int]),
            signup('카톡 공유', AdminColors.chartKakao, ChartMarker.triangle, [for (final r in rows) r['share_count']! as int]),
          ],
          summary: '추이',
          intervals: 4,
          leftPad: 54,
          rightPad: 24,
          legendLeft: 55,
          maxWidth: 1080,
        ),
        width: 1096,
      );

      expect(tester.getSize(key('chart-matching')), const Size(1080, 240));
      expect([for (var i = 0; i < 3; i++) tester.widget<ChartMarkerBox>(key('chart-matching-legend-$i')).marker], [ChartMarker.circle, ChartMarker.square, ChartMarker.triangle]);
      expect(tester.widget<ChartMarkerBox>(key('chart-matching-legend-2')).size, 12);
      for (final tick in ['0', '10', '20', '30', '40']) {
        expect(inChart('matching', find.text(tick)), findsOneWidget, reason: tick);
      }
      expect(
        key('chart-matching-plot'),
        paints
          ..path(color: AdminColors.chartAccept, strokeWidth: 2.5)
          ..path(color: AdminColors.chartMatch, strokeWidth: 2.5)
          ..path(color: AdminColors.chartKakao, strokeWidth: 2.5)
          ..circle(color: AdminColors.chartAccept)
          ..rrect(color: AdminColors.chartMatch)
          ..path(color: AdminColors.chartKakao, style: PaintingStyle.fill),
      );
    });

    testWidgets('모든 값이 0 이면 축과 0 선만 — 선도 끝 표시도 없다, 눈금은 0 · 2 · 4 · 6', (tester) async {
      await pump(tester, signupChart(maleValues: List.filled(30, 0), femaleValues: List.filled(30, 0)));

      expect(key('chart-signups-plot'), isNot(paints..path()));
      expect(key('chart-signups-plot'), isNot(paints..circle()));
      for (final tick in ['0', '2', '4', '6']) {
        expect(inChart('signups', find.text(tick)), findsOneWidget, reason: tick);
      }
    });

    testWidgets('마우스를 올리면 그날 말풍선(ink 바탕 · 12/700 제목 "10/14 (수)" + 줄 "남 가입 n" · "여 가입 n"), 벗어나면 사라진다', (tester) async {
      await pump(tester, signupChart());
      final origin = tester.getTopLeft(key('chart-signups'));
      final plotWidth = 520 - 42 - 16;
      // 26번째 날(10/14, 번호 25): 점 x = 42 + 462 × 25/29
      final mouse = await hover(tester, origin + Offset(42 + plotWidth * 25 / 29, 100));

      expect(find.text('10/14 (수)'), findsOneWidget);
      expect(find.text('남 가입 ${male[25]}'), findsOneWidget);
      expect(find.text('여 가입 ${female[25]}'), findsOneWidget);
      final box = tester.widget<Container>(key('chart-signups-tooltip'));
      expect((box.decoration! as BoxDecoration).color, AdminColors.ink);
      final title = tester.widget<Text>(find.text('10/14 (수)'));
      expect((title.style!.fontSize, title.style!.fontWeight, title.style!.color), (12, FontWeight.w700, AdminColors.onPrimary));

      await mouse.moveTo(const Offset(1300, 800));
      await tester.pump();
      expect(key('chart-signups-tooltip'), findsNothing);
    });

    testWidgets('화면 읽기: 그림 전체가 한 줄 요약으로 읽힌다', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, signupChart());

      expect(find.bySemanticsLabel('최근 30일 가입 합계'), findsOneWidget);
      handle.dispose();
    });
  });

  group('묶음 막대(A2 접수량)', () {
    testWidgets('520×240 — 눈금 3줄(최댓값 15 → 0 · 10 · 20), 날짜 4개 10/5 · 10/9 · 10/13 · 10/18, 범례 신고 · 인증샷', (tester) async {
      await pump(tester, intake);

      expect(tester.getSize(key('chart-intake')), const Size(520, 240));
      for (final tick in ['0', '10', '20']) {
        expect(inChart('intake', find.text(tick)), findsOneWidget, reason: tick);
      }
      for (final date in ['10/5', '10/9', '10/13', '10/18']) {
        expect(inChart('intake', find.text(date)), findsOneWidget, reason: date);
      }
      expect(inChart('intake', find.text('신고')), findsOneWidget);
      expect(inChart('intake', find.text('인증샷')), findsOneWidget);
      expect(tester.widget<ChartMarkerBox>(key('chart-intake-legend-0')).color, AdminColors.chartReport);
      expect(tester.widget<ChartMarkerBox>(key('chart-intake-legend-1')).color, AdminColors.chartProof);
    });

    testWidgets('막대 14일 × 2 = 28개: 신고 chart-report · 인증샷 chart-proof 번갈아', (tester) async {
      await pump(tester, intake);

      final pattern = paints;
      for (var i = 0; i < 14; i++) {
        pattern
          ..rrect(color: AdminColors.chartReport)
          ..rrect(color: AdminColors.chartProof);
      }
      expect(key('chart-intake-plot'), pattern);
    });

    testWidgets('올린 칸 띠(#00000010, 칸 폭 × 눈금 높이)와 말풍선 — 말풍선은 띠 오른쪽 8, 위 9, ink · r8 · 안쪽 12 × 8', (tester) async {
      await pump(tester, intake);
      final origin = tester.getTopLeft(key('chart-intake'));
      final slot = (520 - 44 - 16) / 14;
      await hover(tester, origin + Offset(44 + slot * 9.5, 100));

      expect(find.text('10/14 (수)'), findsOneWidget);
      expect(find.text('신고 8'), findsOneWidget);
      expect(find.text('인증샷 15'), findsOneWidget);
      expect(key('chart-intake-plot'), paints..rect(rect: Rect.fromLTWH(44 + slot * 9, 17, slot, 160), color: const Color(0x10000000)));
      final tip = tester.getRect(key('chart-intake-tooltip'));
      expect(tip.left - origin.dx, closeTo(44 + slot * 10 + 8, 0.5));
      expect(tip.top - origin.dy, 9);
      expect(tip.width, closeTo(88, 4));
      expect(tip.height, 72);
      final decoration = tester.widget<Container>(key('chart-intake-tooltip')).decoration! as BoxDecoration;
      expect((decoration.color, decoration.borderRadius), (AdminColors.ink, BorderRadius.circular(8)));
    });

    testWidgets('오른쪽 끝 칸에서는 말풍선이 띠 왼쪽으로 뒤집힌다(카드 밖으로 나가지 않게)', (tester) async {
      await pump(tester, intake);
      final origin = tester.getTopLeft(key('chart-intake'));
      final slot = (520 - 44 - 16) / 14;
      await hover(tester, origin + Offset(44 + slot * 13.5, 100));

      final tip = tester.getRect(key('chart-intake-tooltip'));
      expect(tip.right - origin.dx, closeTo(44 + slot * 13 - 8, 0.5));
    });

    testWidgets('화면 읽기 요약 한 줄', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, intake);

      expect(find.bySemanticsLabel('최근 14일 접수량 합계'), findsOneWidget);
      handle.dispose();
    });
  });

  group('가로 막대(A2 학교별 활성)', () {
    testWidgets('학교 5곳이면 520×240(= 34 × 5 + 70), 3곳이면 172 — 8곳까지 늘어난다(34 × 8 + 70 = 342)', (tester) async {
      await pump(tester, schools(count: 3));
      expect(tester.getSize(key('chart-schools')), const Size(520, 172));
    });

    testWidgets('눈금 5줄(최댓값 62 → 0 · 20 · 40 · 60 · 80), 학교 이름 12 ink, 막대 끝 숫자 11 chart-axis', (tester) async {
      await pump(tester, schools());

      for (final tick in ['0', '20', '40', '60', '80']) {
        expect(inChart('schools', find.text(tick)), findsWidgets, reason: tick);
      }
      final name = tester.widget<Text>(inChart('schools', find.text('서울대')));
      expect((name.style!.fontSize, name.style!.color), (12, AdminColors.ink));
      final value = tester.widget<Text>(inChart('schools', find.text('62')));
      expect((value.style!.fontSize, value.style!.color), (11, AdminColors.chartAxis));
      expect(inChart('schools', find.text('58')), findsOneWidget);
      // 학교 이름은 왼쪽 맞춤 x 0, 첫 줄은 위 12 아래
      final origin = tester.getTopLeft(key('chart-schools'));
      expect(tester.getTopLeft(inChart('schools', find.text('서울대'))).dx - origin.dx, 0);
    });

    testWidgets('막대: 학교마다 남 · 여 두 개(높이 13, 오른쪽 r3) — 학교 3곳 = 6개, chart-male · chart-female 번갈아', (tester) async {
      await pump(tester, schools());

      final pattern = paints;
      for (var i = 0; i < 3; i++) {
        pattern
          ..rrect(color: AdminColors.chartMale)
          ..rrect(color: AdminColors.chartFemale);
      }
      expect(key('chart-schools-plot'), pattern);
    });

    testWidgets('범례 "남 활성" · "여 활성"(사각 10)은 막대 왼쪽 90, 그림 맨 아래 쪽(y = 34 × 학교 수 + 44)', (tester) async {
      await pump(tester, schools());

      final origin = tester.getTopLeft(key('chart-schools'));
      expect(tester.getTopLeft(key('chart-schools-legend-0')) - origin, const Offset(90, 34 * 3 + 44 + 3));
      expect(inChart('schools', find.text('남 활성')), findsOneWidget);
      expect(inChart('schools', find.text('여 활성')), findsOneWidget);
    });

    testWidgets('마우스를 올리면 그 학교 말풍선: 제목은 학교 전체 이름, 줄 "남 활성 n" · "여 활성 n"', (tester) async {
      await pump(tester, schools());
      final origin = tester.getTopLeft(key('chart-schools'));
      await hover(tester, origin + const Offset(200, 12 + 34 + 10));

      expect(find.text('연세대학교'), findsOneWidget);
      expect(find.text('남 활성 48'), findsOneWidget);
      expect(find.text('여 활성 51'), findsOneWidget);
    });

    testWidgets('화면 읽기 요약 한 줄', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, schools());

      expect(find.bySemanticsLabel('학교별 활성 인원'), findsOneWidget);
      handle.dispose();
    });
  });

  group('그림 높이 · 너비 · 점 위치(값이 눈금과 위치로 정확히 옮겨지는지)', () {
    // 그림 위 17 · 아래 177(높이 160) — 맨 위 눈금이 최댓값, 0 이 바닥
    Widget line(List<int> values) => AdminLineChart(
      name: 'geo',
      dates: const ['2026-10-16', '2026-10-17', '2026-10-18'],
      series: [signup('남', AdminColors.chartMale, ChartMarker.circle, values)],
      summary: '',
      intervals: 3,
      leftPad: 42,
      rightPad: 16,
      legendLeft: 44,
    );

    testWidgets('선: 최댓값(30 = 맨 위 눈금)인 마지막 날 점은 x 504(오른쪽 끝) · y 17(위 끝)', (tester) async {
      await pump(tester, line([0, 15, 30]));
      expect(key('chart-geo-plot'), paints..circle(x: 504, y: 17, radius: 5));
    });

    testWidgets('선: 0 인 마지막 날 점은 y 177(바닥), 가운데 날은 x 273', (tester) async {
      await pump(tester, line([30, 15, 0]));
      expect(key('chart-geo-plot'), paints..circle(x: 504, y: 177, radius: 5));
    });

    testWidgets('선: 값 15(= 최댓값의 절반)는 그림 높이의 절반 y 97, 날짜 순서대로 x 가 늘어난다', (tester) async {
      await pump(tester, line([30, 0, 15]));
      expect(key('chart-geo-plot'), paints..circle(x: 504, y: 97, radius: 5));
      await pump(tester, line([15, 0, 30])); // 첫날이 15 — 점은 마지막 날(30)이라 y 17 이고 x 는 그대로
      expect(key('chart-geo-plot'), paints..circle(x: 504, y: 17, radius: 5));
    });

    testWidgets('선: 점 x 는 날짜 순서대로 첫날 42 · 가운데 날 273 · 마지막 날 504(날짜 글자 가운데가 같은 x — 점 하루 밀기 방지)', (tester) async {
      await pump(tester, line([0, 15, 30]));
      for (final (date, x) in [('10/16', 42.0), ('10/17', 273.0), ('10/18', 504.0)]) {
        expect(tester.getCenter(inChart('geo', find.text(date))).dx, closeTo(x, 0.01), reason: date);
      }
    });

    testWidgets('묶음 막대: 최댓값(20 = 맨 위 눈금) 칸 높이 = 그림 높이 160, 절반 값 10 = 80 — 막대 한 줄이라 칸 가운데 — 첫 칸 x 96.5 · 둘째 칸 x 211.5', (tester) async {
      await pump(
        tester,
        GroupedBarChart(
          name: 'geo',
          dates: const ['2026-10-15', '2026-10-16', '2026-10-17', '2026-10-18'],
          series: [signup('신고', AdminColors.chartReport, ChartMarker.square, [20, 10, 0, 0])],
          summary: '',
          intervals: 2,
          leftPad: 44,
          rightPad: 16,
          legendLeft: 44,
        ),
      );
      RRect bar(double x, double height) => RRect.fromRectAndCorners(
        Rect.fromLTWH(x, 177 - height, 10, height),
        topLeft: const Radius.circular(2),
        topRight: const Radius.circular(2),
      );
      expect(key('chart-geo-plot'), paints..rrect(rrect: bar(96.5, 160))..rrect(rrect: bar(211.5, 80)));
    });

    testWidgets('가로 막대: 최댓값(80 = 맨 오른쪽 눈금) 너비 = 그림 폭 381, 절반 값 40 = 190.5 — 위 12 · 둘째 줄은 14 아래', (tester) async {
      await pump(
        tester,
        HorizontalBarChart(
          name: 'geo',
          labels: const ['서울대'],
          titles: const ['서울대학교'],
          series: [
            signup('남 활성', AdminColors.chartMale, ChartMarker.square, [80]),
            signup('여 활성', AdminColors.chartFemale, ChartMarker.square, [40]),
          ],
          summary: '',
        ),
      );
      RRect bar(double y, double width) => RRect.fromRectAndCorners(
        Rect.fromLTWH(90, y, width, 13),
        topRight: const Radius.circular(3),
        bottomRight: const Radius.circular(3),
      );
      expect(key('chart-geo-plot'), paints..rrect(rrect: bar(12, 381))..rrect(rrect: bar(26, 190.5)));
    });
  });

  group('공용 부품', () {
    test('칸이 하나도 없으면 높이만 차지한다(그림 자리)', () {
      expect(ChartMarker.values, [ChartMarker.circle, ChartMarker.square, ChartMarker.triangle]);
      expect(dateLabelIndexes(0, 5), isEmpty);
    });
  });
}
