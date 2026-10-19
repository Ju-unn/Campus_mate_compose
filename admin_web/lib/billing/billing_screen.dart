import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/billing/billing_controller.dart';
import 'package:campus_mate_admin/billing/billing_item.dart';
import 'package:campus_mate_admin/billing/revenue_chart.dart';
import 'package:campus_mate_admin/heart_tasks/heart_task_item.dart' show formatSubmittedAt;
import 'package:campus_mate_admin/reports/report_item.dart' show missingValue;
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/users/user_item.dart' show storeName;
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_loader.dart';
import 'package:campus_mate_admin/widgets/admin_search_field.dart';
import 'package:campus_mate_admin/widgets/admin_table.dart';
import 'package:campus_mate_admin/widgets/chart_card.dart';
import 'package:campus_mate_admin/widgets/error_row.dart';
import 'package:campus_mate_admin/widgets/stat_card.dart';
import 'package:campus_mate_admin/widgets/status_badge.dart';
import 'package:campus_mate_admin/widgets/table_empty.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// A8 결제 조회(pen w674C · 1200 높이 시안, 내용이 길어 세로로 스크롤). 읽기 전용 — 여기서 하트를 주지 않는다.
/// 내용 32 안쪽, 세로 20: 윗줄(KC7VW, 사이 24 — 이번 달 매출 카드 280 + 주문 · 거래 번호 검색 카드) → 최근 30일 매출 그래프 카드(feZAY) →
/// (조회한 뒤에만) 주문 결과 카드(KF9lR) → "환불됐는데 하트를 다 못 거둔 목록" 제목 · 표(AxOrD) · 안내 → "환불이 잦은 계정" 제목 · 표(pen 없음).
/// 주문 번호는 입력 칸에만 있다 — 조회 뒤에도 칸은 그대로지만(대장 결정 8) 주소 · 라우터 · provider 에는 남기지 않는다.
class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  final TextEditingController _order = TextEditingController();

  @override
  void dispose() {
    _order.dispose();
    super.dispose();
  }

  void _search() => ref.read(orderSearchProvider.notifier).search(_order.text);

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(billingOverviewProvider);
    final orders = ref.watch(orderSearchProvider);
    final data = overview.value;
    final summary = data?.summary;
    final Widget below;
    if (overview.hasError) {
      below = AdminTableEmpty(
        framed: false,
        leading: const Icon(LucideIcons.circleAlert, size: 32, color: AdminColors.danger),
        title: '결제 정보를 불러오지 못했어요',
        body: '인터넷 연결을 확인하고 다시 시도해 주세요.',
        action: AdminButton(label: '다시 시도', variant: AdminButtonVariant.secondary, onPressed: ref.read(billingOverviewProvider.notifier).retry),
        alert: true,
      );
    } else if (data == null) {
      below = const AdminTableEmpty(framed: false, leading: AdminLoader(color: AdminColors.muted), body: '결제 정보를 불러오고 있어요');
    } else {
      below = _ChartCard(days: data.days);
    }
    final children = <Widget>[
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch, // 글자가 커져 한 카드가 길어지면 둘이 같은 높이로
          children: [
            StatCard(
              label: '이번 달 매출 (시험 결제 제외)',
              value: summary == null ? missingValue : formatWon(summary.revenueKrw),
              footer: summary == null
                  ? null
                  : Text(formatMonth(summary.month), style: AdminTypography.smStrong.copyWith(height: AdminTypography.smBox, color: AdminColors.primaryText)),
            ),
            const SizedBox(width: AdminSpacing.lg),
            Expanded(child: _SearchCard(controller: _order, loading: orders?.isLoading ?? false, onSearch: _search)),
          ],
        ),
      ),
      below,
      if (data != null) ...[
        if (orders != null) _OrderResult(orders: orders),
        ..._shortfall(data.shortfall),
        ..._returned(data.returned),
      ] else if (orders != null)
        _OrderResult(orders: orders),
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

  /// 못 거둔 표 위젯들: 제목 → (표 | "다 거두지 못한 구매가 없어요") → 안내(표가 있을 때). 사이는 화면 전체와 같은 20.
  List<Widget> _shortfall(List<ShortfallRow> rows) {
    return [
      Semantics(
        header: true,
        child: Text('환불됐는데 하트를 다 못 거둔 목록', style: AdminTypography.md.copyWith(fontWeight: FontWeight.w700, height: AdminTypography.mdBox, color: AdminColors.ink)),
      ),
      if (rows.isEmpty)
        Text('다 거두지 못한 구매가 없어요', style: AdminTypography.sm.copyWith(height: AdminTypography.smBox, color: AdminColors.muted))
      else ...[
        AdminTable(
          key: const ValueKey('shortfall-table'),
          columns: const [170, 150, 150, 130, 90, 90, 130],
          fillLast: true,
          heads: const ['시각', '닉네임', '상품', '스토어', '지급', '회수', '못 거둔 하트'],
          rows: [
            for (final row in rows)
              AdminTableRow(
                rowKey: ValueKey('shortfall-row-${row.purchaseId}'),
                cells: [
                  AdminCellText(formatSubmittedAt(row.refundedAt)),
                  AdminCellText(row.nickname ?? missingValue),
                  AdminCellText(row.productName),
                  AdminCellText(storeName(row.store)),
                  AdminCellText('${row.grantedHearts}'),
                  AdminCellText('${row.clawedBackHearts}'),
                  AdminCellText('${row.shortfallHearts}'),
                ],
              ),
          ],
        ),
        Text('이미 써서 다 거두지 못한 구매예요. 손으로 줄지 판단할 때 참고해요.', style: AdminTypography.xs.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted)),
      ],
    ];
  }

  /// 환불이 잦은 계정: 제목 → (표 | "환불한 계정이 없어요"). pen 시안이 없어 못 거둔 표와 같은 모양이다. 순서는 서버(환불 건수 많은 순).
  List<Widget> _returned(List<ReturnedAccountRow> rows) {
    return [
      Semantics(
        header: true,
        child: Text('환불이 잦은 계정', style: AdminTypography.md.copyWith(fontWeight: FontWeight.w700, height: AdminTypography.mdBox, color: AdminColors.ink)),
      ),
      if (rows.isEmpty)
        Text('환불한 계정이 없어요', style: AdminTypography.sm.copyWith(height: AdminTypography.smBox, color: AdminColors.muted))
      else
        AdminTable(
          key: const ValueKey('returned-table'),
          columns: const [170, 110, 150, 110, 90, 90, 130],
          fillLast: true,
          heads: const ['닉네임', '환불 건수', '환불 금액', '지급 하트', '회수', '못 거둠', '마지막 환불'],
          rows: [
            for (final row in rows)
              AdminTableRow(
                rowKey: ValueKey('returned-row-${row.profileId}'),
                cells: [
                  AdminCellText(row.nickname ?? missingValue),
                  AdminCellText('${row.refundCount}'),
                  AdminCellText(formatWon(row.refundedKrw)),
                  AdminCellText('${row.grantedHearts}'),
                  AdminCellText('${row.clawedBackHearts}'),
                  AdminCellText('${row.shortfallHearts}'),
                  AdminCellText(formatSubmittedAt(row.lastRefundedAt)),
                ],
              ),
          ],
        ),
    ];
  }
}

BoxDecoration _cardBox() => BoxDecoration(color: AdminColors.surface, borderRadius: BorderRadius.circular(AdminRadius.md));

BoxDecoration _cardBorder() => BoxDecoration(borderRadius: BorderRadius.circular(AdminRadius.md), border: Border.all(color: AdminColors.outline));

/// 검색 카드(v2yWE): 안쪽 24 · 세로 8 — 제목 16/700 → 검색 줄(사이 12: 칸 480×44 + [조회]) → 안내 12 web-muted
class _SearchCard extends StatelessWidget {
  const _SearchCard({required this.controller, required this.loading, required this.onSearch});

  final TextEditingController controller;
  final bool loading;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('order-search-card'),
      constraints: const BoxConstraints(minHeight: StatCard.height),
      padding: const EdgeInsets.all(AdminSpacing.lg),
      decoration: _cardBox(),
      foregroundDecoration: _cardBorder(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text('주문 · 거래 번호로 찾기', style: AdminTypography.md.copyWith(fontWeight: FontWeight.w700, height: AdminTypography.mdBox, color: AdminColors.ink)),
          ),
          const SizedBox(height: AdminSpacing.xs),
          Row(
            children: [
              SizedBox(
                key: const ValueKey('order-search-box'),
                width: 480,
                child: AdminSearchField(
                  controller: controller,
                  hint: '구글 주문 번호 · 애플 거래 번호 (정확히 일치)',
                  sensitive: true,
                  maxChars: 64, // 서버 주문 번호 상한
                  onSubmitted: (_) => onSearch(),
                ),
              ),
              const SizedBox(width: AdminSpacing.sm),
              AdminButton(label: '조회', loading: loading, onPressed: onSearch),
            ],
          ),
          const SizedBox(height: AdminSpacing.xs),
          Text('읽기 전용이에요. 여기서 하트를 주지는 않아요(하트 조정은 사용자 상세).', style: AdminTypography.xs.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted)),
        ],
      ),
    );
  }
}

/// 최근 30일 매출 카드(feZAY): 공용 [ChartCard] — 제목 16/700 + 알약(오른쪽 끝) → 그래프 240
class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.days});

  final List<DailyRevenue> days;

  @override
  Widget build(BuildContext context) {
    return ChartCard(
      key: const ValueKey('revenue-card'),
      pillKey: const ValueKey('revenue-pill'),
      title: '최근 30일 매출 (원)',
      pill: '최근 30일 · 시험 결제 제외',
      child: RevenueChart(days: days),
    );
  }
}

/// 주문 결과(KF9lR): 안쪽 24 · 가로 32 · 칸 6개(세로 6 — 이름 12/600 web-muted → 값 16/700 web-ink). 상태는 배지.
/// 못 찾으면 같은 카드 안에 14 web-muted 한 줄. 받는 중 · 못 받음은 pen 에 없어 같은 카드에 넣는다.
class _OrderResult extends StatelessWidget {
  const _OrderResult({required this.orders});

  final AsyncValue<List<BillingOrder>> orders;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (orders.hasError) {
      final error = orders.error;
      final badNumber = error is AdminApiFailure && error.statusCode == 422;
      content = ErrorRow(badNumber ? '번호 모양이 맞지 않아요. 주문 · 거래 번호를 그대로 붙여 넣어 주세요' : '조회하지 못했어요. 다시 시도해 주세요.');
    } else if (orders.isLoading || !orders.hasValue) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AdminLoader(color: AdminColors.muted),
          const SizedBox(width: AdminSpacing.xs),
          Text('조회하고 있어요', style: AdminTypography.sm.copyWith(height: AdminTypography.smBox, color: AdminColors.muted)),
        ],
      );
    } else if (orders.requireValue.isEmpty) {
      content = Text('그 번호로 찾은 구매가 없어요', style: AdminTypography.sm.copyWith(height: AdminTypography.smBox, color: AdminColors.muted));
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, order) in orders.requireValue.indexed) ...[
            if (i > 0) const SizedBox(height: AdminSpacing.md),
            _OrderRow(order: order),
          ],
        ],
      );
    }
    return Container(
      key: const ValueKey('order-result'),
      padding: const EdgeInsets.all(AdminSpacing.lg),
      decoration: _cardBox(),
      foregroundDecoration: _cardBorder(),
      child: Align(alignment: Alignment.centerLeft, child: content),
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order});

  final BillingOrder order;

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusTone) = purchaseStatusBadge(order.status);
    Widget cell(String name, {String? value, Widget? widget}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: AdminTypography.xsStrong.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted)),
          const SizedBox(height: 6), // pen KF9lR 칸 세로 6 — 간격 표에 없는 값
          widget ?? Text(value!, style: AdminTypography.md.copyWith(fontWeight: FontWeight.w700, height: AdminTypography.mdBox, color: AdminColors.ink)),
        ],
      );
    }

    final cells = [
      cell('상품', value: order.productName),
      cell('스토어', value: storeName(order.store)),
      cell('상태', widget: StatusBadge(statusLabel, tone: statusTone)),
      cell('지급 하트', value: '${order.grantedHearts}'),
      cell('회수한 하트', value: '${order.clawedBackHearts}'),
      cell('시각', value: formatSubmittedAt(order.shownAt)),
    ];
    return Wrap(
      spacing: 32,
      runSpacing: AdminSpacing.md,
      children: cells,
    );
  }
}
