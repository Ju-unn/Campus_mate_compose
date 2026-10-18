import 'dart:async';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/api/cursor_page.dart';
import 'package:campus_mate_admin/gate/gate_controller.dart';
import 'package:campus_mate_admin/home/home_item.dart';
import 'package:campus_mate_admin/matching/matching_item.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:campus_mate_admin/state/paged_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A9 위쪽의 읽기 셋(숫자 카드 · 30일 추이 · 학교 Select 옵션). 화면에 들어올 때마다 새로 받고, 한 가지라도 못 받으면 오류 한 가지.
class MatchingOverview {
  const MatchingOverview({required this.summary, required this.days, required this.universities});

  final MatchingSummary summary;
  final List<DailyMatching> days;
  final List<UniversityStatus> universities;
}

final matchingOverviewProvider = NotifierProvider.autoDispose<MatchingOverviewController, AsyncValue<MatchingOverview>>(MatchingOverviewController.new);

class MatchingOverviewController extends Notifier<AsyncValue<MatchingOverview>> {
  late AdminApi _api;
  int _request = 0;

  @override
  AsyncValue<MatchingOverview> build() {
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
    final MatchingOverview overview;
    try {
      // 학교 Select 옵션은 활성 0 인 학교도(대장 결정 5)
      final parts = await Future.wait<Object>([_api.matchingSummary(), _api.matchingDaily(), _api.universities(includeEmpty: true)]);
      overview = MatchingOverview(
        summary: parts[0] as MatchingSummary,
        days: parts[1] as List<DailyMatching>,
        universities: parts[2] as List<UniversityStatus>,
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

/// 목록 필터(상태 칩 · 학교). 화면에 들어올 때마다 처음 값(전체)으로 돌아온다. null = 전체.
class MatchingFilter {
  const MatchingFilter({this.status, this.university});

  final String? status;
  final String? university;
}

final matchingFilterProvider = NotifierProvider.autoDispose<MatchingFilterController, MatchingFilter>(MatchingFilterController.new);

class MatchingFilterController extends Notifier<MatchingFilter> {
  @override
  MatchingFilter build() => const MatchingFilter();

  // 같은 칩을 다시 눌러도 새 값이라 목록을 새로 받는다(새 매칭 확인).
  void setStatus(String? status) => state = MatchingFilter(status: status, university: state.university);

  void setUniversity(String? university) => state = MatchingFilter(status: state.status, university: university);
}

/// A9 "누가 누구랑 매칭됐나" 목록 — 필터가 바뀌면 처음부터 다시 받는다.
final matchingPairsProvider = NotifierProvider.autoDispose<MatchingPairsController, PagedState<MatchPair>>(MatchingPairsController.new);

class MatchingPairsController extends PagedController<MatchPair> {
  late AdminApi _api;
  late MatchingFilter _filter;

  @override
  PagedState<MatchPair> build() {
    _api = ref.watch(adminApiProvider);
    _filter = ref.watch(matchingFilterProvider);
    return super.build();
  }

  @override
  Future<CursorPage<MatchPair>> fetch(String? before) => _api.matchingPairs(status: _filter.status, university: _filter.university, before: before);
}
