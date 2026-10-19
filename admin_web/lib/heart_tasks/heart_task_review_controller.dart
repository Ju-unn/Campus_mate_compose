import 'dart:async';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/gate/gate_controller.dart';
import 'package:campus_mate_admin/heart_tasks/heart_task_item.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 처리 중인 단추(그 단추에 도는 아이콘을 단다)
enum ReviewAction { approve, reject }

/// A3 한 화면의 상태. 목록은 대기 건 요약, 고른 건은 사진 · 지난 제출까지 받은 한 건.
class HeartTaskReviewState {
  const HeartTaskReviewState({
    this.filter,
    this.items = const AsyncLoading(),
    this.selectedId,
    this.detail,
    this.selectedPhotoIndex = 0,
    this.busy,
    this.reviewFailed = false,
    this.alreadyReviewed = false,
  });

  /// null = 전체
  final HeartTaskKind? filter;
  final AsyncValue<List<HeartTaskItem>> items;
  final String? selectedId;

  /// 고른 건의 사진 · 지난 제출. 고른 건이 없으면 null.
  final AsyncValue<HeartTaskDetail>? detail;

  /// 큰 사진으로 보는 장(0부터). 다른 건을 고르면 0 으로 돌아간다.
  final int selectedPhotoIndex;
  final ReviewAction? busy;

  /// 승인 · 반려 요청이 실패했다(연결 · 5xx) — 카드 안 오류 줄
  final bool reviewFailed;

  /// 다른 관리자가 먼저 처리했다(409 · 링크로 연 건이 이미 처리됨) — "이미 처리된 항목이에요" 대화상자
  final bool alreadyReviewed;

  /// 고른 건의 요약 — 목록에 있으면 그 줄, 없으면(목록 밖 링크) 받아 온 한 건에서
  HeartTaskItem? get selected {
    for (final item in items.value ?? const <HeartTaskItem>[]) {
      if (item.id == selectedId) return item;
    }
    final loaded = detail?.value?.item;
    return loaded?.id == selectedId ? loaded : null;
  }

  /// 사진 · 지난 제출을 다 받았고 처리 중이 아니다 — 승인 · 반려(단추 · 단축키)를 받는다
  bool get canReview => busy == null && detail?.value?.item.id == selectedId && selectedId != null;

  static const Object _keep = Object();

  HeartTaskReviewState copyWith({
    Object? filter = _keep,
    AsyncValue<List<HeartTaskItem>>? items,
    Object? selectedId = _keep,
    Object? detail = _keep,
    int? selectedPhotoIndex,
    Object? busy = _keep,
    bool? reviewFailed,
    bool? alreadyReviewed,
  }) {
    return HeartTaskReviewState(
      filter: identical(filter, _keep) ? this.filter : filter as HeartTaskKind?,
      items: items ?? this.items,
      selectedId: identical(selectedId, _keep) ? this.selectedId : selectedId as String?,
      detail: identical(detail, _keep) ? this.detail : detail as AsyncValue<HeartTaskDetail>?,
      selectedPhotoIndex: selectedPhotoIndex ?? this.selectedPhotoIndex,
      busy: identical(busy, _keep) ? this.busy : busy as ReviewAction?,
      reviewFailed: reviewFailed ?? this.reviewFailed,
      alreadyReviewed: alreadyReviewed ?? this.alreadyReviewed,
    );
  }
}

/// 화면(주소)마다 하나. 인자는 디스코드 링크(`/heart-tasks/{id}`)로 연 건 — 처음 한 번 그 건을 고른다.
/// 다른 메뉴로 나가면 버려지고 돌아오면 목록을 새로 받는다.
final heartTaskReviewProvider = NotifierProvider.autoDispose.family<HeartTaskReviewController, HeartTaskReviewState, String?>(
  HeartTaskReviewController.new,
);

class HeartTaskReviewController extends Notifier<HeartTaskReviewState> {
  HeartTaskReviewController(this.initialId);

  final String? initialId;
  late AdminApi _api;

  /// 늦게 온 목록 응답(필터를 바꾼 뒤)을 버리려고 요청마다 올린다
  int _listRequest = 0;

  /// 사진 오류로 다시 받은 건. 다시 받은 주소도 깨지면 더 받지 않는다(무한 반복 막기) — 사람이 그 줄을 다시 누르면 지운다.
  final Set<String> _photoRetried = <String>{};

  @override
  HeartTaskReviewState build() {
    _api = ref.watch(adminApiProvider);
    // 링크 번호가 제출 번호 꼴이 아니면(`..%2Fme` 등) 쓰지 않고 목록의 첫 건으로 연다.
    final linked = initialId;
    unawaited(_loadList(filter: null, prefer: linked != null && AdminApi.isTaskId(linked) ? linked : null));
    return const HeartTaskReviewState();
  }

  /// 칩. 같은 칩을 다시 눌러도 새로 받는다(새 제출 확인).
  void setFilter(HeartTaskKind? kind) {
    state = state.copyWith(
      filter: kind,
      items: const AsyncLoading(),
      selectedId: null,
      detail: null,
      selectedPhotoIndex: 0,
      reviewFailed: false,
    );
    unawaited(_loadList(filter: kind));
  }

  void retryList() => setFilter(state.filter);

  void retryDetail() {
    final id = state.selectedId;
    if (id != null) unawaited(_fetchDetail(id));
  }

  /// 줄을 누른다 — 그 건의 사진 · 지난 제출을 새로 받는다.
  Future<void> select(String id) {
    _photoRetried.remove(id);
    return _fetchDetail(id);
  }

  Future<bool> approve() => _review(ReviewAction.approve, _api.approveHeartTask);

  Future<bool> reject(HeartTaskRejectReason reason) => _review(ReviewAction.reject, (id) => _api.rejectHeartTask(id, reason));

  /// 썸네일을 눌러 그 장을 큰 사진으로 본다. 받은 장 수 밖이면 무시한다.
  void selectPhoto(int index) {
    final count = state.detail?.value?.photoUrls.length ?? 0;
    if (index < 0 || index >= count) return;
    state = state.copyWith(selectedPhotoIndex: index);
  }

  /// 사진이 그려지지 않았다(서명 만료 · 깨진 파일) — 그 건만 한 번 다시 받는다.
  void photoFailed(String id) {
    if (state.selectedId != id || !_photoRetried.add(id)) return;
    unawaited(_fetchDetail(id));
  }

  void dismissAlreadyReviewed() => state = state.copyWith(alreadyReviewed: false);

  Future<void> _loadList({required HeartTaskKind? filter, String? prefer}) async {
    final request = ++_listRequest;
    final List<HeartTaskItem> items;
    try {
      items = await _api.listHeartTasks(task: filter);
    } on AdminApiFailure catch (failure) {
      if (!_isLatest(request)) return;
      state = state.copyWith(items: AsyncError(failure, StackTrace.current));
      _regateIf(failure);
      return;
    }
    if (!_isLatest(request)) return;
    state = state.copyWith(items: AsyncData(items));
    final keep = prefer ?? state.selectedId;
    if (keep != null && (prefer != null || items.any((i) => i.id == keep))) {
      // 링크로 연 건은 목록 밖이어도 한 건으로 받아 본다(이미 처리됨 · 51번째 이후)
      if (keep != state.selectedId || state.detail?.value == null) await _fetchDetail(keep);
      return;
    }
    await _selectFirst();
  }

  /// 다른 데서 처리됐을 수 있으니 목록만 새로 받는다(지금 줄들은 받을 때까지 그대로 둔다).
  Future<void> _reload() => _loadList(filter: state.filter);

  Future<void> _selectFirst() async {
    final first = state.items.value?.firstOrNull;
    if (first == null) {
      state = state.copyWith(selectedId: null, detail: null);
      return;
    }
    await _fetchDetail(first.id);
  }

  Future<void> _fetchDetail(String id) async {
    // 같은 건을 다시 받는 것(사진 오류 · 같은 줄 다시 누름)이면 고른 장을 두고, 다른 건이면 첫 장부터
    state = state.copyWith(
      selectedId: id,
      detail: const AsyncLoading<HeartTaskDetail>(),
      selectedPhotoIndex: id == state.selectedId ? null : 0,
      reviewFailed: false,
    );
    final HeartTaskDetail detail;
    try {
      detail = await _api.getHeartTask(id);
    } on AdminApiFailure catch (failure) {
      if (!ref.mounted || state.selectedId != id) return;
      _regateIf(failure);
      // 목록 밖 번호(링크가 틀렸거나 지워진 건)는 오류 대신 목록의 첫 건
      final inList = state.items.value?.any((i) => i.id == id) ?? false;
      if (!inList && (failure.statusCode == 404 || failure.statusCode == 422)) return _selectFirst();
      state = state.copyWith(detail: AsyncError<HeartTaskDetail>(failure, StackTrace.current));
      return;
    }
    if (!ref.mounted || state.selectedId != id) return;
    if (!detail.isWaiting) {
      // 다른 탭 · 다른 관리자가 이미 처리했다
      state = state.copyWith(alreadyReviewed: true, selectedId: null, detail: null);
      return _reload();
    }
    // 그 사이 정리로 장수가 줄었으면 첫 장
    final keep = state.selectedPhotoIndex < detail.photoUrls.length ? null : 0;
    state = state.copyWith(detail: AsyncData<HeartTaskDetail>(detail), selectedPhotoIndex: keep);
  }

  Future<bool> _review(ReviewAction action, Future<void> Function(String id) send) async {
    final id = state.selectedId;
    if (id == null || !state.canReview) return false;
    state = state.copyWith(busy: action, reviewFailed: false);
    try {
      await send(id);
    } on AlreadyReviewed {
      if (!ref.mounted) return false;
      state = state.copyWith(busy: null, alreadyReviewed: true);
      await _reload();
      return false;
    } on AdminApiFailure catch (failure) {
      if (!ref.mounted) return false;
      state = state.copyWith(busy: null, reviewFailed: true);
      _regateIf(failure);
      return false;
    }
    if (!ref.mounted) return true;
    final items = state.items.value;
    final rest = [for (final item in items ?? const <HeartTaskItem>[]) if (item.id != id) item];
    if (state.selectedId != id) {
      // 처리하는 사이 다른 줄 · 필터로 옮겼다 — 그 선택은 그대로 두고 처리한 줄만 뺀다.
      // 필터를 바꿔 목록을 새로 받는 중(값 없음)이면 목록도 건드리지 않는다(옛 목록으로 덮지 않게).
      state = state.copyWith(busy: null, items: items == null ? null : AsyncData(rest));
      return true;
    }
    // 같은 필터 안의 다음 건: 처리한 줄 자리에 올라온 줄, 맨 아래였으면 맨 위(가장 오래 기다린 건)
    final index = items?.indexWhere((i) => i.id == id) ?? -1;
    final next = rest.isEmpty ? null : rest[index >= 0 && index < rest.length ? index : 0];
    state = state.copyWith(items: AsyncData(rest), busy: null, selectedId: next?.id, detail: null, selectedPhotoIndex: 0);
    if (next != null) unawaited(select(next.id));
    return true;
  }

  bool _isLatest(int request) => ref.mounted && request == _listRequest;

  /// 401 · 403 — 세션 만료 · 관리자 해제 · 2단계 풀림. 관문이 다시 판정해 로그인 · 권한 없음 화면으로 보낸다.
  void _regateIf(AdminApiFailure failure) {
    if (failure.isGateProblem) ref.read(gateProvider.notifier).retry();
  }
}
