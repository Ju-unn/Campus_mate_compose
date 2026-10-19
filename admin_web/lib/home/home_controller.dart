import 'dart:async';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/gate/gate_controller.dart';
import 'package:campus_mate_admin/home/home_item.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A2 홈의 읽기 네 가지(통계 숫자 · 일별 30일 · 학교별 현황 · 운영 상태판)
class HomeOverview {
  const HomeOverview({required this.stats, required this.days, required this.universities, required this.health});

  final HomeStats stats;

  /// 가입 추이는 30일 전체, 접수량 막대는 마지막 14일
  final List<DailyStat> days;
  final List<UniversityStatus> universities;
  final HealthReport health;
}

/// 홈 첫 화면. 화면에 들어올 때마다 새로 받는다. 한 가지라도 못 받으면 오류 한 가지로 다룬다(다시 시도 한 번으로 넷 다 — 결제 화면과 같다).
final homeOverviewProvider = NotifierProvider.autoDispose<HomeOverviewController, AsyncValue<HomeOverview>>(HomeOverviewController.new);

class HomeOverviewController extends Notifier<AsyncValue<HomeOverview>> {
  late AdminApi _api;
  int _request = 0;

  @override
  AsyncValue<HomeOverview> build() {
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
    final HomeOverview overview;
    try {
      final parts = await Future.wait<Object>([_api.homeStats(), _api.statsDaily(), _api.universities(), _api.health()]);
      overview = HomeOverview(
        stats: parts[0] as HomeStats,
        days: parts[1] as List<DailyStat>,
        universities: parts[2] as List<UniversityStatus>,
        health: parts[3] as HealthReport,
      );
    } on AdminApiFailure catch (failure) {
      if (!ref.mounted || request != _request) return;
      state = AsyncError(failure, StackTrace.current);
      if (failure.isGateProblem) ref.read(gateProvider.notifier).retry();
      return;
    }
    if (ref.mounted && request == _request) state = AsyncData(overview);
  }
}
