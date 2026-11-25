import 'dart:async';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/api/list_page.dart';
import 'package:campus_mate_admin/gate/gate_controller.dart';
import 'package:campus_mate_admin/notices/notice_item.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:campus_mate_admin/reports/report_controller.dart' show ActionResult;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 공지 목록의 화면 상태. [moreFailed] 는 [더 보기] 실패(받아 둔 줄은 그대로 두고 아래에 오류 줄).
class NoticeListState {
  const NoticeListState({
    this.items = const [],
    this.hasMore = false,
    this.loading = true,
    this.failed = false,
    this.loadingMore = false,
    this.moreFailed = false,
  });

  final List<NoticeItem> items;
  final bool hasMore;

  /// 첫 쪽을 받는 중
  final bool loading;
  final bool failed;
  final bool loadingMore;
  final bool moreFailed;
}

/// 공지 목록 — 화면에 들어올 때마다 첫 쪽부터 받고, [더 보기] 는 마지막 줄 커서로 다음 쪽을 이어 붙인다.
/// 늦게 온 응답(다시 받기를 시작한 뒤)은 버린다. 401 · 403 은 관문이 다시 판정한다(PagedController 와 같다).
final noticeListProvider = NotifierProvider.autoDispose<NoticeListController, NoticeListState>(NoticeListController.new);

class NoticeListController extends Notifier<NoticeListState> {
  late AdminApi _api;
  int _request = 0;

  @override
  NoticeListState build() {
    _api = ref.watch(adminApiProvider);
    unawaited(_fetch(null));
    return const NoticeListState();
  }

  /// 첫 쪽부터 다시(못 받음 뒤 [다시 시도] · 쓰기 · 지우기 뒤)
  void reload() {
    state = const NoticeListState();
    unawaited(_fetch(null));
  }

  void loadMore() {
    final current = state;
    if (current.loadingMore || !current.hasMore || current.items.isEmpty) return;
    state = NoticeListState(items: current.items, hasMore: true, loading: false, loadingMore: true);
    unawaited(_fetch(current.items.last));
  }

  Future<void> _fetch(NoticeItem? after) async {
    final request = ++_request;
    final CursorPage<NoticeItem> page;
    try {
      page = await _api.listNotices(after: after);
    } on AdminApiFailure catch (failure) {
      if (!ref.mounted || request != _request) return;
      state = after == null
          ? const NoticeListState(loading: false, failed: true)
          : NoticeListState(items: state.items, hasMore: true, loading: false, moreFailed: true);
      _regateIf(failure);
      return;
    }
    if (!ref.mounted || request != _request) return;
    state = NoticeListState(items: [if (after != null) ...state.items, ...page.items], hasMore: page.hasMore, loading: false);
  }

  /// 쓰기. 성공이면 null(목록을 첫 쪽부터 다시 받는다), 실패면 그 실패 — 대화상자가 [noticeSaveErrorText] 로 글자를 고른다.
  Future<AdminApiFailure?> create({required String title, required String body, NoticeImage? image}) async {
    try {
      await _api.createNotice(title: title, body: body, image: image);
    } on AdminApiFailure catch (failure) {
      _regateIf(failure);
      return failure;
    }
    if (ref.mounted) reload();
    return null;
  }

  /// 지우기(사유 필수). 성공하면 목록을 첫 쪽부터 다시 받는다. 404(다른 관리자가 먼저 지움)도 실패 글자는 그대로 두고
  /// 목록만 다시 받아 지워진 줄을 없앤다.
  Future<ActionResult> delete(String id, String reason) async {
    try {
      await _api.deleteNotice(id, reason);
    } on AdminApiFailure catch (failure) {
      _regateIf(failure);
      if (ref.mounted && failure.statusCode == 404) reload();
      return ActionResult.failed;
    }
    if (ref.mounted) reload();
    return ActionResult.done;
  }

  void _regateIf(AdminApiFailure failure) {
    if (ref.mounted && failure.isGateProblem) ref.read(gateProvider.notifier).retry();
  }
}
