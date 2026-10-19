import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/charts/chart_parts.dart';
import 'package:campus_mate_admin/charts/chart_scale.dart';
import 'package:campus_mate_admin/charts/line_chart.dart';
import 'package:campus_mate_admin/billing/billing_item.dart' show formatMonthDay;
import 'package:campus_mate_admin/matching/matching_controller.dart';
import 'package:campus_mate_admin/matching/matching_item.dart';
import 'package:campus_mate_admin/reports/report_item.dart' show missingValue;
import 'package:campus_mate_admin/shell/admin_section.dart';
import 'package:campus_mate_admin/state/paged_controller.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_chip.dart';
import 'package:campus_mate_admin/widgets/admin_link.dart';
import 'package:campus_mate_admin/widgets/admin_select.dart';
import 'package:campus_mate_admin/widgets/admin_table.dart';
import 'package:campus_mate_admin/widgets/chart_card.dart';
import 'package:campus_mate_admin/widgets/error_row.dart';
import 'package:campus_mate_admin/widgets/load_states.dart';
import 'package:campus_mate_admin/widgets/stat_card.dart';
import 'package:campus_mate_admin/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// A9 매칭 현황(pen H5Pocy · 1440×1200, 내용이 길어 세로로 스크롤). 내용 32 안쪽, 세로 20: 숫자 카드 4장(사이 16, 폭 fill) →
/// 추이 카드(수락 · 매칭 · 카톡 공유 선 3줄) → 표 제목 → 필터 줄(학교 Select + 상태 칩 4개) → 안내 줄 → 표 → (더 보기) → 안내.
/// 사진 · 카톡 아이디 · 대화는 서버도 주지 않고 표에도 열이 없다. 닉네임을 누르면 사용자 상세(A5).
class MatchingScreen extends ConsumerWidget {
  const MatchingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(matchingOverviewProvider);
    final data = overview.value;
    final list = ref.watch(matchingPairsProvider);
    final filter = ref.watch(matchingFilterProvider);
    final filters = ref.read(matchingFilterProvider.notifier);

    final children = <Widget>[
      if (overview.hasError)
        ErrorBlock('매칭 정보를 불러오지 못했어요', onRetry: ref.read(matchingOverviewProvider.notifier).retry)
      else if (data == null)
        const LoadingBlock('매칭 정보를 불러오고 있어요')
      else ...[
        _StatRow(summary: data.summary),
        _TrendCard(days: data.days),
      ],
      Semantics(
        header: true,
        child: Text('누가 누구랑 매칭됐나', style: AdminTypography.md.copyWith(fontWeight: FontWeight.w700, height: AdminTypography.mdBox, color: AdminColors.ink)),
      ),
      _FilterRow(
        universities: [for (final u in data?.universities ?? const []) (u.id, u.name)],
        filter: filter,
        onStatus: filters.setStatus,
        onUniversity: filters.setUniversity,
      ),
      Row(
        children: [
          const Icon(LucideIcons.info, size: 16, color: AdminColors.muted),
          const SizedBox(width: AdminSpacing.xs),
          Text('사진 · 카톡 아이디 · 대화는 보이지 않아요. 최근 순으로 보여요.', style: AdminTypography.xs.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted)),
        ],
      ),
      ..._list(context, ref, list),
    ];
    return Padding(
      padding: const EdgeInsets.all(AdminSpacing.xl),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, child) in children.indexed) ...[if (i > 0) const SizedBox(height: 20), child],
          ],
        ),
      ),
    );
  }

  /// 목록 자리: 받는 중 · 못 받음 · 빈 목록, 아니면 표 → (더 보기) → 안내
  List<Widget> _list(BuildContext context, WidgetRef ref, PagedState<MatchPair> list) {
    final controller = ref.read(matchingPairsProvider.notifier);
    if (list.loading) return const [LoadingBlock('매칭 목록을 불러오고 있어요')];
    if (list.failed) return [ErrorBlock('매칭 목록을 불러오지 못했어요', onRetry: controller.retry)];
    if (list.items.isEmpty) return const [EmptyBlock('조건에 맞는 매칭이 없어요')];
    return [
      AdminTable(
        key: const ValueKey('match-table'),
        columns: const [160, 250, 40, 250, 160, 170],
        fillLast: true,
        heads: const ['매칭 시각', 'A (닉네임 · 학교)', '', 'B (닉네임 · 학교)', '상태', '카톡 공유 시각'],
        rows: [
          for (final pair in list.items)
            AdminTableRow(
              rowKey: ValueKey('match-row-${pair.id}'),
              cells: [
                AdminCellText(formatMonthDayTime(pair.matchedAt)),
                _PersonCell(person: pair.a, linkKey: ValueKey('match-${pair.id}-a')),
                Text('—', style: AdminTypography.sm.copyWith(color: AdminColors.muted)),
                _PersonCell(person: pair.b, linkKey: ValueKey('match-${pair.id}-b')),
                Builder(
                  builder: (context) {
                    final (label, tone) = matchStatusBadge(pair.status);
                    // 글자를 키우면 배지가 칸(160)을 넘으니 칸 폭에 맞춰 줄인다
                    return FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: StatusBadge(label, tone: tone));
                  },
                ),
                pair.sharedAt == null
                    ? Text('-', style: AdminTypography.sm.copyWith(color: AdminColors.muted))
                    : AdminCellText(formatMonthDayTime(pair.sharedAt!)),
              ],
            ),
        ],
      ),
      if (list.hasMore) _MoreButton(loading: list.loadingMore, failed: list.moreFailed, onPressed: controller.loadMore),
      Text('닉네임을 누르면 사용자 상세로 가요.', style: AdminTypography.xs.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted)),
    ];
  }
}

/// 숫자 카드 4장(DAui6): 폭 fill · 사이 16. 아래 줄(14 muted)은 서버가 값을 준 것만 — "어제 n건"은 accepts_yesterday 가 있을 때만.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.summary});

  final MatchingSummary summary;

  @override
  Widget build(BuildContext context) {
    Widget? note(String text) => Text(text, style: AdminTypography.sm.copyWith(height: AdminTypography.smBox, color: AdminColors.muted));
    final yesterday = summary.acceptsYesterday;
    final cards = [
      StatCard(
        fill: true,
        label: '오늘 수락 / 누적 수락',
        value: '${summary.acceptsToday} / ${summary.acceptsTotal}',
        footer: yesterday == null ? null : note('어제 $yesterday건'),
      ),
      StatCard(fill: true, label: '수락한 사람 수', value: '${summary.acceptersTotal}명', footer: note('누적')),
      StatCard(fill: true, label: '매칭 성립 쌍', value: '${summary.matchesTotal}쌍', footer: note('누적')),
      StatCard(fill: true, label: '카톡 공유 쌍', value: '${summary.sharedTotal}쌍 · ${summary.shareRatePercent}', footer: note('매칭 대비')),
    ];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch, // 글자가 커져 한 카드가 길어지면 넷이 같은 높이로
        children: [
          for (final (i, card) in cards.indexed) ...[if (i > 0) const SizedBox(width: AdminSpacing.md), Expanded(child: card)],
        ],
      ),
    );
  }
}

/// 추이 카드(I2DMO): 제목 + 알약 "최근 30일" → Line(Match) 1080×240. 수락 chart-accept 원 · 매칭 chart-match 사각 · 카톡 공유 chart-kakao 삼각, 눈금 5줄.
class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.days});

  final List<DailyMatching> days;

  @override
  Widget build(BuildContext context) {
    final accept = [for (final d in days) d.acceptCount];
    final match = [for (final d in days) d.matchCount];
    final share = [for (final d in days) d.shareCount];
    return ChartCard(
      key: const ValueKey('matching-card'),
      pillKey: const ValueKey('matching-pill'),
      title: '수락 · 매칭 · 카톡 공유 추이',
      pill: '최근 30일',
      child: AdminLineChart(
        name: 'matching',
        dates: [for (final d in days) d.date],
        series: [
          ChartSeries(name: '수락', color: AdminColors.chartAccept, marker: ChartMarker.circle, values: accept),
          ChartSeries(name: '매칭', color: AdminColors.chartMatch, marker: ChartMarker.square, values: match),
          ChartSeries(name: '카톡 공유', color: AdminColors.chartKakao, marker: ChartMarker.triangle, values: share),
        ],
        summary: _summary(days, accept, match, share),
        intervals: 4,
        leftPad: 54,
        rightPad: 24,
        legendLeft: 55,
        maxWidth: 1080,
      ),
    );
  }

  /// 화면 읽기용 한 줄: "최근 30일 수락 합계 n건 · 매칭 n쌍 · 카톡 공유 n쌍, 가장 많은 날 M/D 수락 n건"(모두 0 이면 합계만)
  static String _summary(List<DailyMatching> days, List<int> accept, List<int> match, List<int> share) {
    int sum(List<int> line) => line.fold<int>(0, (a, b) => a + b);
    final head = '최근 ${days.length}일 수락 합계 ${sum(accept)}건 · 매칭 ${sum(match)}쌍 · 카톡 공유 ${sum(share)}쌍';
    if (days.isEmpty || sum(accept) + sum(match) + sum(share) == 0) return head;
    final best = peakIndex([accept, match, share]);
    return '$head, 가장 많은 날 ${formatMonthDay(days[best].date)} 수락 ${accept[best]}건 · 매칭 ${match[best]}쌍 · 카톡 공유 ${share[best]}쌍';
  }
}

/// 필터 줄(rMflW): 학교 Select(200×36 "전체 학교") + 칩 "전체" · "대화 중" · "카톡 공유 완료" · "닫힘"(36), 사이 12
class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.universities, required this.filter, required this.onStatus, required this.onUniversity});

  final List<(String, String)> universities;
  final MatchingFilter filter;
  final ValueChanged<String?> onStatus;
  final ValueChanged<String?> onUniversity;

  @override
  Widget build(BuildContext context) {
    const chips = <(String?, String)>[(null, '전체'), ('chatting', '대화 중'), ('shared', '카톡 공유 완료'), ('closed', '닫힘')];
    return Row(
      children: [
        AdminSelect<String?>(
          key: const ValueKey('school-select'),
          semanticLabel: '학교 고르기',
          options: [(null, '전체 학교'), for (final (id, name) in universities) (id, name)],
          value: filter.university,
          onChanged: onUniversity,
        ),
        for (final (status, label) in chips) ...[
          const SizedBox(width: AdminSpacing.sm),
          AdminChip(label: label, selected: filter.status == status, onTap: () => onStatus(status)),
        ],
      ],
    );
  }
}

/// A · B 칸: "닉네임 · 학교" 14/600 primary-text 링크 → 그 사람의 사용자 상세. 탈퇴로 없는 사람은 링크 없이 "탈퇴한 사용자"(muted).
/// 주소에 넣을 수 없는 모양의 id(경로 id 검사 — [AdminApi.isTaskId])는 글자만 보이고 링크는 만들지 않는다. 서버 글자는 일반 Text 로만 그린다.
class _PersonCell extends StatelessWidget {
  const _PersonCell({required this.person, required this.linkKey});

  final MatchPerson person;
  final Key linkKey;

  @override
  Widget build(BuildContext context) {
    if (person.withdrawn) return Text('탈퇴한 사용자', style: AdminTypography.sm.copyWith(color: AdminColors.muted));
    final label = '${person.nickname} · ${person.university ?? missingValue}';
    final id = person.id!;
    if (!AdminApi.isTaskId(id)) return Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AdminTypography.smStrong.copyWith(color: AdminColors.ink));
    return AdminLink(key: linkKey, label: label, onTap: () => context.go('${AdminSection.users.path}/$id'));
  }
}

/// 표 아래 [더 보기](Secondary) — 실패하면 단추 위에 오류 줄(앞 줄은 그대로)
class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.loading, required this.failed, required this.onPressed});

  final bool loading;
  final bool failed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (failed) ...[
          const ErrorRow('더 불러오지 못했어요. 다시 시도해 주세요.', lineHeight: AdminTypography.xsBox),
          const SizedBox(height: AdminSpacing.xs),
        ],
        AdminButton(label: '더 보기', variant: AdminButtonVariant.secondary, loading: loading, onPressed: onPressed),
      ],
    );
  }
}
