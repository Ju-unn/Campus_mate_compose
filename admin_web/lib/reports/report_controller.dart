import 'dart:async';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/gate/gate_controller.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:campus_mate_admin/reports/report_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 목록 필터(종류 · 상태). 상세에 갔다 "← 신고 목록" 으로 와도 남게 화면 밖(앱이 켜진 동안)에 둔다.
class ReportFilter {
  const ReportFilter({this.type, this.status = ReportStatus.open});

  /// null = 전체
  final ReportTargetType? type;
  final ReportStatus status;
}

final reportFilterProvider = NotifierProvider<ReportFilterController, ReportFilter>(ReportFilterController.new);

class ReportFilterController extends Notifier<ReportFilter> {
  @override
  ReportFilter build() => const ReportFilter();

  // 같은 칩을 다시 눌러도 새 값이라 목록을 새로 받는다(새 신고 확인).
  void setType(ReportTargetType? type) => state = ReportFilter(type: type, status: state.status);

  void setStatus(ReportStatus status) => state = ReportFilter(type: state.type, status: status);
}

/// A4 목록. 화면에 들어올 때마다 새로 받는다(조치 · 409 뒤 목록 새로 받기는 이것으로 된다).
/// Riverpod 의 자동 재시도를 쓰지 않으려고 실패를 상태로 들고 있다(W1 과 같은 방식).
final reportListProvider = NotifierProvider.autoDispose<ReportListController, AsyncValue<List<ReportSummary>>>(
  ReportListController.new,
);

class ReportListController extends Notifier<AsyncValue<List<ReportSummary>>> {
  late AdminApi _api;

  /// 늦게 온 응답(필터를 바꾼 뒤)을 버리려고 요청마다 올린다
  int _request = 0;

  @override
  AsyncValue<List<ReportSummary>> build() {
    _api = ref.watch(adminApiProvider);
    ref.listen(reportFilterProvider, (_, _) => reload());
    unawaited(_load());
    return const AsyncLoading();
  }

  void reload() {
    state = const AsyncLoading();
    unawaited(_load());
  }

  Future<void> _load() async {
    final request = ++_request;
    final filter = ref.read(reportFilterProvider);
    final List<ReportSummary> items;
    try {
      items = await _api.listReports(status: filter.status, type: filter.type);
    } on AdminApiFailure catch (failure) {
      if (!_isLatest(request)) return;
      state = AsyncError(failure, StackTrace.current);
      if (failure.isGateProblem) ref.read(gateProvider.notifier).retry();
      return;
    }
    if (_isLatest(request)) state = AsyncData(items);
  }

  bool _isLatest(int request) => ref.mounted && request == _request;
}

/// 조치 한 번의 결과
enum ActionResult {
  done,

  /// 다른 관리자가 먼저 처리했다(409) — 상세는 이미 새로 받는 중
  alreadyDone,

  /// 연결 · 서버 실패 — 대화상자에 오류 줄
  failed,

  /// 기각은 됐는데 이어 부른 가림 해제가 실패했다 — 조치 카드에 오류 줄
  unhideFailed,
}

/// 메모 없이 "가림도 함께 해제하기" 를 켰을 때 가림 해제 사유(서버는 사유 필수). 대장 결정 필요 항목으로 보고.
const String dismissUnhideReason = '신고 기각';

/// A4 상세 한 건(주소 `/reports/{id}` 마다 하나). 조치는 여기서 보내고 성공 · 409 뒤 상세를 새로 받는다.
final reportDetailProvider = NotifierProvider.autoDispose.family<ReportDetailController, AsyncValue<ReportDetail>, String>(
  ReportDetailController.new,
);

class ReportDetailController extends Notifier<AsyncValue<ReportDetail>> {
  ReportDetailController(this.id);

  final String id;
  late AdminApi _api;
  int _request = 0;

  @override
  AsyncValue<ReportDetail> build() {
    _api = ref.watch(adminApiProvider);
    unawaited(_load());
    return const AsyncLoading();
  }

  void retry() {
    state = const AsyncLoading();
    unawaited(_load());
  }

  /// 조치 뒤 — 지금 내용은 새로 받을 때까지 그대로 둔다(깜빡이지 않게)
  Future<void> refresh() => _load();

  Future<ActionResult> actOnProfile(ProfileAction action, String reason) {
    final target = state.value?.summary.target;
    if (target == null) return Future.value(ActionResult.failed);
    return _act(() => _api.actOnProfile(target.id, action, reason));
  }

  Future<ActionResult> setContent({required bool blind, required String reason}) {
    final summary = state.value?.summary;
    if (summary == null || !summary.type.isContent) return Future.value(ActionResult.failed);
    return _act(() => _api.setContentStatus(summary.type, summary.targetId, blind: blind, reason: reason));
  }

  /// 조치 완료 / 기각. [unhide] 면 기각이 된 뒤 가림 해제를 같은 글로 이어 부른다(먼저 부르면 가림 해제가 이 신고까지
  /// 기각해 닫기가 409 가 된다). 가림이 이미 풀렸으면(409) 성공과 같다.
  Future<ActionResult> resolve(ReportStatus outcome, {required String note, required bool sameTarget, required bool unhide}) async {
    final target = state.value?.summary.target;
    final closed = await _act(() => _api.resolveReport(id, outcome, note: note, sameTarget: sameTarget), refreshAfter: false);
    if (closed != ActionResult.done) return closed;
    var result = ActionResult.done;
    if (unhide && target != null) {
      final reason = note.trim().isEmpty ? dismissUnhideReason : note;
      try {
        await _api.actOnProfile(target.id, ProfileAction.unhide, reason);
      } on AlreadyReviewed {
        // 다른 관리자가 먼저 풀었다 — 바라던 상태다
      } on AdminApiFailure catch (failure) {
        _regateIf(failure);
        result = ActionResult.unhideFailed;
      }
    }
    if (ref.mounted) unawaited(refresh());
    return result;
  }

  /// 채팅 앞뒤 — 받은 줄은 돌려주기만 하고 들고 있지 않는다(대화상자가 닫히면 버려진다)
  Future<(ActionResult, List<ChatLine>?)> viewChat(String reason) async {
    try {
      return (ActionResult.done, await _api.chatContext(id, reason));
    } on AdminApiFailure catch (failure) {
      _regateIf(failure);
      return (ActionResult.failed, null);
    }
  }

  Future<ActionResult> _act(Future<void> Function() send, {bool refreshAfter = true}) async {
    try {
      await send();
    } on AlreadyReviewed {
      if (ref.mounted) unawaited(refresh());
      return ActionResult.alreadyDone;
    } on AdminApiFailure catch (failure) {
      _regateIf(failure);
      return ActionResult.failed;
    }
    if (refreshAfter && ref.mounted) unawaited(refresh());
    return ActionResult.done;
  }

  Future<void> _load() async {
    final request = ++_request;
    final ReportDetail detail;
    try {
      detail = await _api.getReport(id);
    } on AdminApiFailure catch (failure) {
      if (!_isLatest(request)) return;
      state = AsyncError(failure, StackTrace.current);
      _regateIf(failure);
      return;
    }
    if (_isLatest(request)) state = AsyncData(detail);
  }

  bool _isLatest(int request) => ref.mounted && request == _request;

  /// 401 · 403 — 관문이 다시 판정해 로그인 · 권한 없음 화면으로 보낸다
  void _regateIf(AdminApiFailure failure) {
    if (failure.isGateProblem && ref.mounted) ref.read(gateProvider.notifier).retry();
  }
}
