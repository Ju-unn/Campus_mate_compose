import 'package:campus_mate_admin/billing/billing_item.dart' show formatMonthDay;
import 'package:campus_mate_admin/charts/chart_parts.dart';
import 'package:campus_mate_admin/charts/chart_scale.dart';
import 'package:campus_mate_admin/charts/grouped_bar_chart.dart';
import 'package:campus_mate_admin/charts/horizontal_bar_chart.dart';
import 'package:campus_mate_admin/charts/line_chart.dart';
import 'package:campus_mate_admin/heart_tasks/heart_task_item.dart' show formatSubmittedAt;
import 'package:campus_mate_admin/home/health_panel.dart';
import 'package:campus_mate_admin/home/home_controller.dart';
import 'package:campus_mate_admin/home/home_item.dart';
import 'package:campus_mate_admin/reports/report_item.dart' show missingValue;
import 'package:campus_mate_admin/shell/admin_section.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/admin_link.dart';
import 'package:campus_mate_admin/widgets/admin_table.dart';
import 'package:campus_mate_admin/widgets/chart_card.dart';
import 'package:campus_mate_admin/widgets/load_states.dart';
import 'package:campus_mate_admin/widgets/stat_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// A2 홈(pen kud26 · 1440×1400, 내용이 길어 세로로 스크롤). 내용 32 안쪽, 세로 24: 인사말 "오늘 처리할 일"(20/700) → 통계 카드 3장(사이 24) →
/// 차트 줄 1(가입 추이 · 접수량, 카드 560 × 2 사이 16) → 줄 2(학교별 활성 인원 · 학교별 현황 표) → 운영 상태판(폭 520).
/// 통계 카드 링크: 검수 대기 → 인증샷 검수 · 열린 신고 → 신고 · 오늘 가입 → 사용자(대장 결정 3).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(homeOverviewProvider);
    final data = overview.value;
    final Widget body;
    if (overview.hasError) {
      body = ErrorBlock('홈 정보를 불러오지 못했어요', onRetry: ref.read(homeOverviewProvider.notifier).retry);
    } else if (data == null) {
      body = const LoadingBlock('홈 정보를 불러오고 있어요');
    } else {
      body = _HomeBody(data: data);
    }
    return Padding(
      padding: const EdgeInsets.all(AdminSpacing.xl),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text('오늘 처리할 일', style: AdminTypography.lg.copyWith(color: AdminColors.ink))),
            const SizedBox(height: AdminSpacing.lg),
            body,
          ],
        ),
      ),
    );
  }
}

/// 접수량 막대가 보여 주는 날 수(pen: 최근 14일)
const int _intakeDays = 14;

/// 학교별 가로 막대에 그리는 학교 수(활성 많은 순 — 서버 순서 그대로, 대장 결정 3)
const int _schoolBars = 8;

class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.data});

  final HomeOverview data;

  @override
  Widget build(BuildContext context) {
    final stats = data.stats;
    void open(AdminSection section) => context.go(section.path);
    final children = <Widget>[
      Row(
        children: [
          StatCard(label: '검수 대기', value: '${stats.pendingProofs}', footer: AdminLink(label: '열기 →', onTap: () => open(AdminSection.heartTasks))),
          const SizedBox(width: AdminSpacing.lg),
          StatCard(label: '열린 신고', value: '${stats.openReports}', footer: AdminLink(label: '열기 →', onTap: () => open(AdminSection.reports))),
          const SizedBox(width: AdminSpacing.lg),
          StatCard(label: '오늘 가입', value: '${stats.signupsToday}', footer: AdminLink(label: '사용자 보기 →', onTap: () => open(AdminSection.users))),
        ],
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _SignupCard(days: data.days)),
          const SizedBox(width: AdminSpacing.md),
          Expanded(child: _IntakeCard(days: data.days)),
        ],
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _SchoolsCard(universities: data.universities)),
          const SizedBox(width: AdminSpacing.md),
          Expanded(child: _SchoolTable(universities: data.universities)),
        ],
      ),
      Align(alignment: Alignment.centerLeft, child: SizedBox(width: 520, child: HealthPanel(health: data.health))),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, child) in children.indexed) ...[if (i > 0) const SizedBox(height: AdminSpacing.lg), child],
      ],
    );
  }
}

/// 가입 추이(cPdMl): 남 가입 chart-male 원 · 여 가입 chart-female 사각, 눈금 4줄
class _SignupCard extends StatelessWidget {
  const _SignupCard({required this.days});

  final List<DailyStat> days;

  @override
  Widget build(BuildContext context) {
    final male = [for (final d in days) d.maleSignups];
    final female = [for (final d in days) d.femaleSignups];
    return ChartCard(
      key: const ValueKey('signup-card'),
      title: '가입 추이',
      pill: '최근 30일',
      child: AdminLineChart(
        name: 'signups',
        dates: [for (final d in days) d.date],
        series: [
          ChartSeries(name: '남 가입', color: AdminColors.chartMale, marker: ChartMarker.circle, values: male),
          ChartSeries(name: '여 가입', color: AdminColors.chartFemale, marker: ChartMarker.square, values: female),
        ],
        summary: _summary('가입', days.length, ['남', '여'], [male, female], [for (final d in days) d.date], '명'),
        intervals: 3,
        leftPad: 42,
        rightPad: 16,
        legendLeft: 44,
      ),
    );
  }
}

/// 접수량(HWkVo): 같은 30일 응답의 마지막 14일, 신고 chart-report · 인증샷 chart-proof
class _IntakeCard extends StatelessWidget {
  const _IntakeCard({required this.days});

  final List<DailyStat> days;

  @override
  Widget build(BuildContext context) {
    final recent = days.length > _intakeDays ? days.sublist(days.length - _intakeDays) : days;
    final reports = [for (final d in recent) d.reportCount];
    final proofs = [for (final d in recent) d.proofCount];
    return ChartCard(
      key: const ValueKey('intake-card'),
      title: '접수량',
      pill: '최근 14일',
      child: GroupedBarChart(
        name: 'intake',
        dates: [for (final d in recent) d.date],
        series: [
          ChartSeries(name: '신고', color: AdminColors.chartReport, marker: ChartMarker.square, values: reports),
          ChartSeries(name: '인증샷', color: AdminColors.chartProof, marker: ChartMarker.square, values: proofs),
        ],
        summary: _summary('접수량', recent.length, ['신고', '인증샷'], [reports, proofs], [for (final d in recent) d.date], '건'),
        intervals: 2,
        leftPad: 44,
        rightPad: 16,
        legendLeft: 44,
      ),
    );
  }
}

/// 화면 읽기용 한 줄: "최근 30일 가입 합계 남 n명 · 여 n명, 가장 많은 날 M/D n명". 값이 모두 0 이면 합계만.
String _summary(String what, int dayCount, List<String> names, List<List<int>> lines, List<String> dates, String unit) {
  final totals = [for (final line in lines) line.fold<int>(0, (a, b) => a + b)];
  final head = '최근 $dayCount일 $what 합계 ${[for (final (i, name) in names.indexed) '$name ${totals[i]}$unit'].join(' · ')}';
  if (totals.every((t) => t == 0)) return head;
  final best = peakIndex(lines);
  return '$head, 가장 많은 날 ${formatMonthDay(dates[best])} ${lines.fold<int>(0, (sum, line) => sum + line[best])}$unit';
}

class _SchoolsCard extends StatelessWidget {
  const _SchoolsCard({required this.universities});

  final List<UniversityStatus> universities;

  @override
  Widget build(BuildContext context) {
    final shown = universities.take(_schoolBars).toList();
    final Widget chart;
    if (shown.isEmpty) {
      chart = SizedBox(
        height: 240,
        child: Center(child: Text('아직 보여 줄 학교가 없어요', style: AdminTypography.sm.copyWith(height: AdminTypography.smBox, color: AdminColors.muted))),
      );
    } else {
      final male = [for (final u in shown) u.maleActive];
      final female = [for (final u in shown) u.femaleActive];
      var best = 0;
      for (final (i, _) in shown.indexed) {
        if (male[i] + female[i] > male[best] + female[best]) best = i; // 같으면 서버 순서가 앞인 학교
      }
      chart = HorizontalBarChart(
        name: 'schools',
        labels: [for (final u in shown) shortSchoolName(u.name)],
        titles: [for (final u in shown) u.name],
        series: [
          ChartSeries(name: '남 활성', color: AdminColors.chartMale, marker: ChartMarker.square, values: male),
          ChartSeries(name: '여 활성', color: AdminColors.chartFemale, marker: ChartMarker.square, values: female),
        ],
        summary: '학교별 활성 인원 ${shown.length}곳, 가장 많은 학교 ${shown[best].name} 남 ${male[best]}명 · 여 ${female[best]}명',
      );
    }
    return ChartCard(key: const ValueKey('schools-card'), title: '학교별 활성 인원', pill: '현재', child: chart);
  }
}

/// 학교별 현황(ChaAF): 제목 16/700 → 12 → 표(서버가 준 학교 전부). 카드 오픈 시각은 한국 시각 그대로.
class _SchoolTable extends StatelessWidget {
  const _SchoolTable({required this.universities});

  final List<UniversityStatus> universities;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('학교별 현황', style: AdminTypography.md.copyWith(fontWeight: FontWeight.w700, height: AdminTypography.mdBox, color: AdminColors.ink)),
        ),
        const SizedBox(height: AdminSpacing.sm),
        if (universities.isEmpty)
          Text('아직 보여 줄 학교가 없어요', style: AdminTypography.sm.copyWith(height: AdminTypography.smBox, color: AdminColors.muted))
        else
          AdminTable(
            key: const ValueKey('school-table'),
            columns: const [170, 180, 100, 100],
            fillLast: true,
            heads: const ['학교', '카드 오픈 시각', '남 활성', '여 활성'],
            rows: [
              for (final u in universities)
                AdminTableRow(
                  rowKey: ValueKey('school-row-${u.id}'),
                  cells: [
                    AdminCellText(u.name),
                    AdminCellText(u.cardOpensAt == null ? missingValue : formatSubmittedAt(u.cardOpensAt!)),
                    AdminCellText('${u.maleActive}'),
                    AdminCellText('${u.femaleActive}'),
                  ],
                ),
            ],
          ),
      ],
    );
  }
}
