import 'package:campus_mate_admin/charts/chart_parts.dart';
import 'package:campus_mate_admin/charts/chart_scale.dart' show peakIndex;
import 'package:campus_mate_admin/charts/time_bar_chart.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:campus_mate_admin/reports/report_item.dart' show missingValue;
import 'package:campus_mate_admin/server_status/server_status_models.dart';
import 'package:campus_mate_admin/shell/nav_badges.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/chart_card.dart';
import 'package:campus_mate_admin/widgets/load_states.dart';
import 'package:campus_mate_admin/widgets/stat_card.dart';
import 'package:campus_mate_admin/widgets/tap_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// pen A11 블록 사이 · 패널 안쪽 20(YAdMU · lEunR) — 간격 표에 없는 값
const double _block = 20;

/// pen A11 [새로고침] · [확인] 높이(R5aHkD · lEunR)
const double _smallButton = 36;

/// 패널에 보이는 이상 줄 수. 넘는 것은 "외 N건" 한 줄(pen 에 없음 — 대장 판단 11-17).
const int _shownAnomalies = 10;

/// 프로젝트 경로는 넣지 않는다 — 콘솔 첫 화면에서 고른다(실제 프로젝트 id 를 코드에 두지 않는다).
const String crashlyticsUrl = 'https://console.firebase.google.com/';

/// A11 서버 상태(pen YAdMU · 이상 없음 siTuo). 내용 안쪽 32, 블록 사이 20: 이상 목록 패널 → 숫자 카드 4장 → 그래프 2개 → Crashlytics 링크.
/// 숫자는 셸이 처음 뜰 때 한 번과 [새로고침] 때만 읽는다(자동 새로고침 없음 — 구글 읽기 비용).
class ServerStatusScreen extends ConsumerWidget {
  const ServerStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(serverStatusProvider);
    final status = state.status;
    final Widget body;
    if (status != null) {
      body = _Body(status: status);
    } else if (state.failure != null) {
      body = ErrorBlock('서버 상태를 불러오지 못했어요', onRetry: ref.read(serverStatusProvider.notifier).refresh);
    } else {
      body = const LoadingBlock('서버 상태를 불러오고 있어요');
    }
    return Padding(
      padding: const EdgeInsets.all(AdminSpacing.xl),
      child: SingleChildScrollView(child: body),
    );
  }
}

/// TopBar 의 "마지막 갱신 HH:mm"(한국 시간) + [새로고침](pen RefreshControl R5aHkD). 도는 동안 단추가 막히고 앞 숫자는 그대로다.
class ServerRefreshControl extends ConsumerWidget {
  const ServerRefreshControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(serverStatusProvider);
    final checkedAt = state.status?.checkedAt;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (checkedAt != null) ...[
          Text('마지막 갱신 ${formatKstTime(checkedAt)}', style: AdminTypography.sm.copyWith(height: AdminTypography.smBox, color: AdminColors.muted)),
          const SizedBox(width: AdminSpacing.sm),
        ],
        AdminButton(
          label: '새로고침',
          variant: AdminButtonVariant.secondary,
          height: _smallButton,
          loading: state.loading,
          onPressed: () {
            ref.read(serverStatusProvider.notifier).refresh();
            ref.read(pendingCountsProvider.notifier).refresh();
          },
        ),
      ],
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.status});

  final ServerStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = <Widget>[
      _AnomalyPanel(status: status),
      _StatRow(now: status.now),
      _ChartRow(buckets: status.buckets),
      Align(
        alignment: Alignment.centerLeft,
        child: TapBox(
          onTap: () => ref.read(linkOpenerProvider)(crashlyticsUrl),
          radius: 4,
          cursor: SystemMouseCursors.click,
          semanticLabel: '앱 꺼짐은 Firebase Crashlytics 에서 보기',
          child: Text(
            '앱 꺼짐은 Firebase Crashlytics 에서 보기 →',
            style: AdminTypography.xsStrong.copyWith(height: AdminTypography.xsBox, color: AdminColors.primaryText),
          ),
        ),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, child) in children.indexed) ...[if (i > 0) const SizedBox(height: _block), child],
      ],
    );
  }
}

/// pen AnomalyPanel(lEunR · 이상 없음 JByhz): web-surface · web-outline 1 · 모서리 14 · 안쪽 20 · 간격 16.
/// 줄은 최신 순, [확인]으로 본 줄은 흐리게(설명 web-muted · 점 web-disabled — pen 에 없는 상태, 대비 4.5 이상인 토큰으로).
class _AnomalyPanel extends ConsumerWidget {
  const _AnomalyPanel({required this.status});

  final ServerStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seen = ref.watch(serverSeenProvider);
    final anomalies = status.anomalies;
    final shape = BorderRadius.circular(AdminRadius.md);
    final shown = anomalies.take(_shownAnomalies).toList();
    final rest = anomalies.length - shown.length;
    final rowText = AdminTypography.sm.copyWith(height: AdminTypography.smBox);
    final title = Semantics(
      header: true,
      child: Text('이상 목록', style: AdminTypography.md.copyWith(fontWeight: FontWeight.w700, height: AdminTypography.mdBox, color: AdminColors.ink)),
    );
    final Widget head;
    final List<Widget> rows;
    if (anomalies.isEmpty) {
      head = Row(
        children: [
          const Icon(LucideIcons.circleCheck, size: AdminSizes.navIcon, color: AdminColors.success),
          const SizedBox(width: AdminSpacing.sm),
          title,
        ],
      );
      rows = [Text('최근 3시간 이상 없음', style: rowText.copyWith(color: AdminColors.muted))];
    } else {
      head = Row(
        children: [
          const Icon(LucideIcons.triangleAlert, size: AdminSizes.navIcon, color: AdminColors.danger),
          const SizedBox(width: AdminSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 2), // pen Title Col 간격 2
                Text('확인하면 왼쪽 메뉴의 숫자가 사라져요', style: AdminTypography.xs.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted)),
              ],
            ),
          ),
          AdminButton(
            label: '확인',
            height: _smallButton,
            onPressed: () => ref.read(serverSeenProvider.notifier).confirm(status),
          ),
        ],
      );
      rows = [
        for (final (i, anomaly) in shown.indexed) ...[
          if (i > 0) const SizedBox(height: AdminSpacing.sm),
          _AnomalyRow(index: i, anomaly: anomaly, seen: seen.contains(anomalyKey(anomaly))),
        ],
        if (rest > 0) ...[const SizedBox(height: AdminSpacing.sm), Text('외 $rest건', style: rowText.copyWith(color: AdminColors.muted))],
      ];
    }
    return Container(
      key: const ValueKey('anomaly-panel'),
      padding: const EdgeInsets.all(_block),
      decoration: BoxDecoration(color: AdminColors.surface, borderRadius: shape),
      foregroundDecoration: BoxDecoration(borderRadius: shape, border: Border.all(color: AdminColors.outline)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [head, const SizedBox(height: AdminSpacing.md), ...rows],
      ),
    );
  }
}

/// pen AnomalyRow(vdiey): 빨간 점 8 → 12 → 시각 14/600 web-muted(폭 44) → 12 → 설명 14 web-ink, 줄 높이 19
class _AnomalyRow extends StatelessWidget {
  const _AnomalyRow({required this.index, required this.anomaly, required this.seen});

  final int index;
  final StatusAnomaly anomaly;

  /// 확인한 줄 — 흐리게
  final bool seen;

  @override
  Widget build(BuildContext context) {
    final text = AdminTypography.sm.copyWith(height: AdminTypography.smBox);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6), // pen 점 y 6(줄 19 안)
          child: Container(
            key: ValueKey('anomaly-dot-$index'),
            width: AdminSizes.badgeDot,
            height: AdminSizes.badgeDot,
            decoration: BoxDecoration(color: seen ? AdminColors.disabled : AdminColors.danger, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: AdminSpacing.sm),
        SizedBox(
          width: 44, // pen 시각 칸 폭
          child: Text(formatKstTime(anomaly.at), maxLines: 1, softWrap: false, style: AdminTypography.smStrong.copyWith(height: AdminTypography.smBox, color: AdminColors.muted)),
        ),
        const SizedBox(width: AdminSpacing.sm),
        Expanded(child: Text(anomalyText(anomaly), style: text.copyWith(color: seen ? AdminColors.muted : AdminColors.ink))),
      ],
    );
  }
}

/// 숫자 카드 4장(기존 StatCard, 한 줄 4칸 · 사이 16). 보조 줄은 pen 14/600 web-muted.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.now});

  final StatusNow now;

  @override
  Widget build(BuildContext context) {
    final p50 = now.p50Ms;
    final p95 = now.p95Ms;
    final instances = now.instances;
    final cards = [
      ('요청 수', '${trimNumber(now.requestsPerMin, 1)}/분', '최근 15분 평균'),
      ('오류 비율', '${(now.errorRate * 100).toStringAsFixed(1)}%', '최근 15분 · 5% 넘으면 이상'),
      ('응답 속도', p50 == null ? missingValue : '${(p50 / 1000).toStringAsFixed(2)}초', '100건 중 95번째 ${p95 == null ? missingValue : '${trimNumber(p95 / 1000, 2)}초'}'),
      ('켜진 서버', instances == null ? missingValue : '$instances대', '지금 일하는 서버'),
    ];
    final footer = AdminTypography.smStrong.copyWith(height: AdminTypography.smBox, color: AdminColors.muted);
    return Row(
      children: [
        for (final (i, (label, value, note)) in cards.indexed) ...[
          if (i > 0) const SizedBox(width: AdminSpacing.md),
          Expanded(child: StatCard(label: label, value: value, fill: true, footer: Text(note, style: footer))),
        ],
      ],
    );
  }
}

/// 그래프 두 개(기존 ChartCard 560×316 · 사이 16, 알약 "최근 3시간"): ① 요청 수 chart-male ② 서버 오류(5xx) chart-report + 점선 기준 3건.
/// ② 에 느린 요청 선은 없다 — 서버가 칸마다 느린 요청 수를 주지 않는다(대장 결정 11-17).
class _ChartRow extends StatelessWidget {
  const _ChartRow({required this.buckets});

  final List<StatusBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final times = [for (final b in buckets) b.start];
    final requests = [for (final b in buckets) b.requests];
    final errors = [for (final b in buckets) b.errors5xx];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ChartCard(
            key: const ValueKey('requests-card'),
            title: '요청 수 (5분마다)',
            pill: '최근 3시간',
            child: TimeBarChart(
              name: 'requests',
              times: times,
              series: ChartSeries(name: '요청 수', color: AdminColors.chartMale, marker: ChartMarker.square, values: requests),
              summary: _summary('요청 수', times, requests),
              intervals: 3,
            ),
          ),
        ),
        const SizedBox(width: AdminSpacing.md),
        Expanded(
          child: ChartCard(
            key: const ValueKey('errors-card'),
            title: '서버 오류 (5분마다)',
            pill: '최근 3시간',
            child: TimeBarChart(
              name: 'errors',
              times: times,
              series: ChartSeries(name: '서버 오류', color: AdminColors.chartReport, marker: ChartMarker.square, values: errors),
              summary: _summary('서버 오류', times, errors),
              intervals: 2,
              threshold: 3,
              thresholdLabel: '이상 기준 3건',
            ),
          ),
        ),
      ],
    );
  }
}

/// 화면 읽기용 한 줄: "최근 3시간 요청 수 합계 n건, 가장 많은 때 HH:mm n건". 모두 0 이면 합계만.
String _summary(String what, List<DateTime> times, List<int> values) {
  final total = values.fold<int>(0, (a, b) => a + b);
  final head = '최근 3시간 $what 합계 $total건';
  if (total == 0) return head;
  final best = peakIndex([values]);
  return '$head, 가장 많은 때 ${formatKstTime(times[best])} ${values[best]}건';
}
