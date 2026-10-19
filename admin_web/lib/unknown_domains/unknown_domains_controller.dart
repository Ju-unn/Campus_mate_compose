import 'dart:async';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/gate/gate_controller.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:campus_mate_admin/unknown_domains/unknown_domain_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A6 표. 화면에 들어올 때마다 새로 받는다. 읽기 전용 — 쪽 나누기 없이 서버가 주는 많은 순 위쪽(기본 200곳)을 그대로.
final unknownDomainsProvider = NotifierProvider.autoDispose<UnknownDomainsController, AsyncValue<List<UnknownDomain>>>(UnknownDomainsController.new);

class UnknownDomainsController extends Notifier<AsyncValue<List<UnknownDomain>>> {
  late AdminApi _api;
  int _request = 0;

  @override
  AsyncValue<List<UnknownDomain>> build() {
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
    final List<UnknownDomain> rows;
    try {
      rows = await _api.unknownDomains();
    } on AdminApiFailure catch (failure) {
      if (!ref.mounted || request != _request) return;
      state = AsyncError(failure, StackTrace.current);
      if (failure.isGateProblem) ref.read(gateProvider.notifier).retry();
      return;
    }
    if (ref.mounted && request == _request) state = AsyncData(rows);
  }
}
