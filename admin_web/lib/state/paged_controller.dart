import 'dart:async';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/api/list_page.dart';
import 'package:campus_mate_admin/gate/gate_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 번호로 쪽을 나눠 받는 목록(매칭 · 작업 기록 · 문의 · 미등록 학교 메일)의 화면 상태.
class PagedState<T> {
  const PagedState({this.items = const [], this.total = 0, this.page = 1, this.loading = true, this.failed = false});

  final List<T> items;

  /// 같은 필터의 전체 건수
  final int total;

  /// 지금 쪽(1부터)
  final int page;

  /// 받는 중(필터 · 쪽을 바꿔 다시 받는 중 포함)
  final bool loading;
  final bool failed;
}

/// 목록 컨트롤러 공통 틀. 하위는 [fetch] 로 한 쪽을 받는다. 필터가 바뀌면(하위가 `ref.watch` 한 값) build 가 다시 불려 1쪽부터 받는다.
/// 늦게 온 응답(필터 · 쪽을 바꾼 뒤 · 다시 시도)은 버린다. 401 · 403 은 관문이 다시 판정한다. 자동 재시도는 쓰지 않고 실패를 상태로 둔다(W1 과 같다).
abstract class PagedController<T> extends Notifier<PagedState<T>> {
  int _request = 0;

  Future<ListPage<T>> fetch(int page);

  @override
  PagedState<T> build() {
    unawaited(_load(1));
    return const PagedState();
  }

  /// 받기 실패 뒤 [다시 시도] — 그 쪽을 다시 받는다
  void retry() => goTo(state.page);

  void goTo(int page) {
    state = PagedState(total: state.total, page: page);
    unawaited(_load(page));
  }

  /// [settle] 이 참이면 빈 쪽이 범위 밖이어도 그대로 둔다 — 마지막 쪽으로 다시 받는 건 한 번뿐(끝없이 돌지 않게).
  Future<void> _load(int page, {bool settle = false}) async {
    final request = ++_request;
    final ListPage<T> result;
    try {
      result = await fetch(page);
    } on AdminApiFailure catch (failure) {
      if (!ref.mounted || request != _request) return;
      state = PagedState(total: state.total, page: page, loading: false, failed: true);
      if (failure.isGateProblem) ref.read(gateProvider.notifier).retry();
      return;
    }
    if (!ref.mounted || request != _request) return;
    // 보던 쪽이 그사이 사라졌다(다른 관리자가 처리해 건수가 줄었다) — 빈 쪽에 갇히지 않게 마지막 쪽을 다시 받는다.
    final last = lastPage(result.total, AdminApi.pageSize);
    if (!settle && result.items.isEmpty && result.total > 0 && page > last) {
      state = PagedState(total: result.total, page: last);
      return _load(last, settle: true);
    }
    state = PagedState(items: result.items, total: result.total, page: page, loading: false);
  }
}
