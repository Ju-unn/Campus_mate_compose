import 'dart:async';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/billing/billing_item.dart';
import 'package:campus_mate_admin/gate/gate_controller.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 결제 조회 화면의 읽기 세 가지(이번 달 매출 · 30일 일 매출 · 못 거둔 목록)
class BillingOverview {
  const BillingOverview({required this.summary, required this.days, required this.shortfall});

  final BillingSummary summary;
  final List<DailyRevenue> days;
  final List<ShortfallRow> shortfall;
}

/// A8 첫 화면. 화면에 들어올 때마다 새로 받는다. 한 가지라도 못 받으면 오류 한 가지로 다룬다(다시 시도 한 번으로 셋 다).
final billingOverviewProvider = NotifierProvider.autoDispose<BillingOverviewController, AsyncValue<BillingOverview>>(
  BillingOverviewController.new,
);

class BillingOverviewController extends Notifier<AsyncValue<BillingOverview>> {
  late AdminApi _api;
  int _request = 0;

  @override
  AsyncValue<BillingOverview> build() {
    _api = ref.watch(adminApiProvider);
    unawaited(_load());
    return const AsyncLoading();
  }

  void retry() {
    state = const AsyncLoading();
    unawaited(_load());
  }

  Future<void> _load() async {
    final request = ++_request;
    final BillingOverview overview;
    try {
      // 하나라도 실패하면 그 실패를 던진다(나머지 실패는 Future.wait 가 삼킨다)
      final parts = await Future.wait<Object>([_api.billingSummary(), _api.billingDaily(), _api.billingShortfall()]);
      overview = BillingOverview(
        summary: parts[0] as BillingSummary,
        days: parts[1] as List<DailyRevenue>,
        shortfall: parts[2] as List<ShortfallRow>,
      );
    } on AdminApiFailure catch (failure) {
      if (!_isLatest(request)) return;
      state = AsyncError(failure, StackTrace.current);
      if (failure.isGateProblem) ref.read(gateProvider.notifier).retry();
      return;
    }
    if (_isLatest(request)) state = AsyncData(overview);
  }

  bool _isLatest(int request) => ref.mounted && request == _request;
}

/// 주문 · 거래 번호 조회 결과. null = 아직 조회하지 않음. **번호는 어디에도 들고 있지 않는다** — 칸 글자는 화면의 입력 칸에만 있고,
/// 응답의 번호 칸도 모델이 읽지 않는다(대장 결정 8 · 설계 §14-3). 화면을 떠나면 결과도 버린다.
final orderSearchProvider = NotifierProvider.autoDispose<OrderSearchController, AsyncValue<List<BillingOrder>>?>(OrderSearchController.new);

class OrderSearchController extends Notifier<AsyncValue<List<BillingOrder>>?> {
  int _request = 0;

  @override
  AsyncValue<List<BillingOrder>>? build() => null;

  /// [order] 는 이 호출 안에서만 쓰고 어디에도 두지 않는다
  Future<void> search(String order) async {
    final text = order.trim();
    if (text.isEmpty) return;
    final request = ++_request;
    state = const AsyncLoading();
    final List<BillingOrder> found;
    try {
      found = await ref.read(adminApiProvider).findOrders(text);
    } on AdminApiFailure catch (failure) {
      if (!ref.mounted || request != _request) return;
      state = AsyncError(failure, StackTrace.current);
      if (failure.isGateProblem) ref.read(gateProvider.notifier).retry();
      return;
    }
    if (ref.mounted && request == _request) state = AsyncData(found);
  }
}
