import 'dart:async';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/api/cursor_page.dart';
import 'package:campus_mate_admin/gate/gate_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 커서로 쪽을 나눠 받는 목록(매칭 · 작업 기록)의 화면 상태.
class PagedState<T> {
  const PagedState({this.items = const [], this.next, this.loading = true, this.failed = false, this.loadingMore = false, this.moreFailed = false});

  final List<T> items;

  /// 다음 쪽 커서(서버 `next_before`) — null 이면 마지막 쪽
  final String? next;

  /// 처음 받는 중(필터를 바꿔 다시 받는 중 포함)
  final bool loading;

  /// 처음 받기 실패
  final bool failed;
  final bool loadingMore;

  /// [더 보기] 실패 — 앞 줄은 그대로 둔다
  final bool moreFailed;

  bool get hasMore => next != null;
}

/// 목록 컨트롤러 공통 틀. 하위는 [fetch] 로 한 쪽을 받는다. 필터가 바뀌면(하위가 `ref.watch` 한 값) build 가 다시 불려 처음부터 받는다.
/// 늦게 온 응답(필터를 바꾼 뒤 · 다시 시도)은 버린다. 401 · 403 은 관문이 다시 판정한다. 자동 재시도는 쓰지 않고 실패를 상태로 둔다(W1 과 같다).
abstract class PagedController<T> extends Notifier<PagedState<T>> {
  int _request = 0;

  /// [before] 는 앞 쪽의 `next_before`(처음이면 null)
  Future<CursorPage<T>> fetch(String? before);

  @override
  PagedState<T> build() {
    unawaited(_load(null));
    return const PagedState();
  }

  /// 처음 받기 실패 뒤 [다시 시도]
  void retry() {
    state = const PagedState();
    unawaited(_load(null));
  }

  void loadMore() {
    final next = state.next;
    if (next == null || state.loadingMore) return;
    state = PagedState(items: state.items, next: next, loading: false, loadingMore: true);
    unawaited(_load(next));
  }

  Future<void> _load(String? before) async {
    final request = ++_request;
    final CursorPage<T> page;
    try {
      page = await fetch(before);
    } on AdminApiFailure catch (failure) {
      if (!ref.mounted || request != _request) return;
      state = before == null
          ? const PagedState(loading: false, failed: true)
          : PagedState(items: state.items, next: before, loading: false, moreFailed: true);
      if (failure.isGateProblem) ref.read(gateProvider.notifier).retry();
      return;
    }
    if (!ref.mounted || request != _request) return;
    state = PagedState(items: [...(before == null ? const [] : state.items), ...page.items], next: page.nextBefore, loading: false);
  }
}
