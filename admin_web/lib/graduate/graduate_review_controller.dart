import 'dart:async';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/gate/gate_controller.dart';
import 'package:campus_mate_admin/graduate/graduate_item.dart';
import 'package:campus_mate_admin/heart_tasks/heart_task_review_controller.dart' show ReviewAction;
import 'package:campus_mate_admin/home/home_item.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'package:campus_mate_admin/heart_tasks/heart_task_review_controller.dart' show ReviewAction;

const String reviewFailedText = '처리하지 못했어요. 다시 시도해 주세요.';
const String invalidInputText = '입력한 값이 맞지 않아요. 문서확인번호 · 학번을 다시 확인해 주세요.';

/// A10 한 화면의 상태. 목록은 대기 건 요약, 고른 건은 사진 · 글자 인식 · 경고까지 받은 한 건.
///
/// 문서확인번호 · 학번 입력값은 이 상태에만 있고(승인 · 반려가 끝나면 비운다) [toString] · 오류 문구 · 로그에 싣지 않는다.
class GraduateReviewState {
  const GraduateReviewState({
    this.items = const AsyncLoading(),
    this.selectedId,
    this.detail,
    this.universities = const AsyncLoading(),
    this.universityChoice,
    this.documentNumber = '',
    this.studentNumber = '',
    this.busy,
    this.error,
    this.alreadyReviewed = false,
  });

  final AsyncValue<List<GraduateItem>> items;
  final String? selectedId;

  /// 고른 건의 한 건. 고른 건이 없으면 null.
  final AsyncValue<GraduateDetail>? detail;

  /// 학교 고르기 선택지(이름순). 학교 목록을 못 받아도 신청 화면은 열린다.
  final AsyncValue<List<UniversityStatus>> universities;

  /// 관리자가 직접 고른 학교. null 이면 글자 인식이 제안한 학교를 미리 채워 보인다.
  final String? universityChoice;
  final String documentNumber;
  final String studentNumber;
  final ReviewAction? busy;

  /// 카드 안 오류 줄 글자(처리 실패 · 409 이유). 없으면 null.
  final String? error;

  /// 다른 관리자가 먼저 처리했다(409 · 이미 결정된 건을 열었다) — "이미 처리된 항목이에요" 대화상자
  final bool alreadyReviewed;

  GraduateItem? get selected {
    for (final item in items.value ?? const <GraduateItem>[]) {
      if (item.id == selectedId) return item;
    }
    final loaded = detail?.value?.item;
    return loaded?.id == selectedId ? loaded : null;
  }

  bool get canReview => busy == null && detail?.value?.id == selectedId && selectedId != null;

  /// 화면에 보이는 학교: 관리자가 고른 것, 없으면 글자 인식이 제안한 첫 학교
  String? get universityId => universityChoice ?? detail?.value?.ocr?.suggestedUniversityIds.firstOrNull;
  bool get universityChosenByAdmin => universityChoice != null;

  /// 학교 목록을 받았고(고른 학교를 눈으로 확인할 수 있고) 학교가 정해졌고, 번호가 정규화 규칙(영숫자 4~40자)에 맞고, 학번은 비었거나 규칙(1~20자)에 맞다 — 승인 단추 · 단축키
  bool get canApprove {
    if (!canReview || !universities.hasValue || universityId == null || normalizeDocumentNumber(documentNumber) == null) return false;
    return studentNumber.trim().isEmpty || normalizeStudentNumber(studentNumber) != null;
  }

  static const Object _keep = Object();

  GraduateReviewState copyWith({
    AsyncValue<List<GraduateItem>>? items,
    Object? selectedId = _keep,
    Object? detail = _keep,
    AsyncValue<List<UniversityStatus>>? universities,
    Object? universityChoice = _keep,
    String? documentNumber,
    String? studentNumber,
    Object? busy = _keep,
    Object? error = _keep,
    bool? alreadyReviewed,
  }) {
    return GraduateReviewState(
      items: items ?? this.items,
      selectedId: identical(selectedId, _keep) ? this.selectedId : selectedId as String?,
      detail: identical(detail, _keep) ? this.detail : detail as AsyncValue<GraduateDetail>?,
      universities: universities ?? this.universities,
      universityChoice: identical(universityChoice, _keep) ? this.universityChoice : universityChoice as String?,
      documentNumber: documentNumber ?? this.documentNumber,
      studentNumber: studentNumber ?? this.studentNumber,
      busy: identical(busy, _keep) ? this.busy : busy as ReviewAction?,
      error: identical(error, _keep) ? this.error : error as String?,
      alreadyReviewed: alreadyReviewed ?? this.alreadyReviewed,
    );
  }

  /// 입력 평문(번호 · 학번 · 글자 인식 번호)은 찍지 않는다.
  @override
  String toString() => 'GraduateReviewState(selectedId: $selectedId, busy: $busy, error: ${error != null}, alreadyReviewed: $alreadyReviewed)';
}

/// 화면(주소)마다 하나. 인자는 `/graduates/{id}` 로 연 건 — 처음 한 번 그 건을 고른다.
final graduateReviewProvider = NotifierProvider.autoDispose.family<GraduateReviewController, GraduateReviewState, String?>(
  GraduateReviewController.new,
);

class GraduateReviewController extends Notifier<GraduateReviewState> {
  GraduateReviewController(this.initialId);

  final String? initialId;
  late AdminApi _api;

  int _listRequest = 0;

  /// 사진 오류로 다시 받은 건(다시 받은 주소도 깨지면 더 받지 않는다 — 사람이 그 줄을 다시 누르면 지운다)
  final Set<String> _photoRetried = <String>{};

  /// 지금 입력 칸이 어느 건의 것인가. 같은 건을 다시 받아도(사진 새로 받기 · 같은 줄 다시 누름) 입력을 지우지 않는다.
  String? _draftFor;

  @override
  GraduateReviewState build() {
    _api = ref.watch(adminApiProvider);
    final linked = initialId;
    unawaited(_loadList(prefer: linked != null && AdminApi.isTaskId(linked) ? linked : null));
    unawaited(_loadUniversities());
    return const GraduateReviewState();
  }

  void retryList() {
    state = state.copyWith(items: const AsyncLoading(), selectedId: null, detail: null, error: null);
    unawaited(_loadList());
  }

  void retryDetail() {
    final id = state.selectedId;
    if (id != null) unawaited(_fetchDetail(id));
  }

  void retryUniversities() {
    state = state.copyWith(universities: const AsyncLoading());
    unawaited(_loadUniversities());
  }

  Future<void> select(String id) {
    _photoRetried.remove(id);
    return _fetchDetail(id);
  }

  void setUniversity(String? id) => state = state.copyWith(universityChoice: id);

  void setDocumentNumber(String text) => state = state.copyWith(documentNumber: text);

  void setStudentNumber(String text) => state = state.copyWith(studentNumber: text);

  Future<bool> approve() {
    final universityId = state.universityId;
    if (!state.canApprove || universityId == null) return Future.value(false);
    final document = state.documentNumber;
    final student = state.studentNumber;
    return _review(
      ReviewAction.approve,
      (id) => _api.approveGraduate(id, universityId: universityId, documentNumber: document, studentNumber: student),
    );
  }

  Future<bool> reject(GraduateRejectReason reason) => _review(ReviewAction.reject, (id) => _api.rejectGraduate(id, reason));

  /// 사진이 그려지지 않았다(서명 만료 · 깨진 파일) — 그 건만 한 번 다시 받는다.
  void photoFailed(String id) {
    if (state.selectedId != id || !_photoRetried.add(id)) return;
    unawaited(_fetchDetail(id));
  }

  void dismissAlreadyReviewed() => state = state.copyWith(alreadyReviewed: false);

  Future<void> _loadUniversities() async {
    final List<UniversityStatus> rows;
    try {
      rows = await _api.universities(includeEmpty: true);
    } on AdminApiFailure catch (failure) {
      if (!ref.mounted) return;
      state = state.copyWith(universities: AsyncError(failure, StackTrace.current));
      _regateIf(failure);
      return;
    }
    if (!ref.mounted) return;
    state = state.copyWith(universities: AsyncData([...rows]..sort((a, b) => a.name.compareTo(b.name))));
  }

  Future<void> _loadList({String? prefer}) async {
    final request = ++_listRequest;
    final List<GraduateItem> items;
    try {
      items = await _api.listGraduateRequests();
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
      if (keep != state.selectedId || state.detail?.value == null) await _fetchDetail(keep);
      return;
    }
    await _selectFirst();
  }

  Future<void> _reload() => _loadList();

  Future<void> _selectFirst() async {
    final first = state.items.value?.firstOrNull;
    if (first == null) {
      _draftFor = null;
      state = state.copyWith(selectedId: null, detail: null, universityChoice: null, documentNumber: '', studentNumber: '');
      return;
    }
    await _fetchDetail(first.id);
  }

  Future<void> _fetchDetail(String id) async {
    state = state.copyWith(selectedId: id, detail: const AsyncLoading<GraduateDetail>(), error: null);
    final GraduateDetail detail;
    try {
      detail = await _api.fetchGraduateRequest(id);
    } on AdminApiFailure catch (failure) {
      if (!ref.mounted || state.selectedId != id) return;
      _regateIf(failure);
      // 목록 밖 번호(링크가 틀렸거나 지워진 건)는 오류 대신 목록의 첫 건
      final inList = state.items.value?.any((i) => i.id == id) ?? false;
      if (!inList && (failure.statusCode == 404 || failure.statusCode == 422)) return _selectFirst();
      state = state.copyWith(detail: AsyncError<GraduateDetail>(failure, StackTrace.current));
      return;
    }
    if (!ref.mounted || state.selectedId != id) return;
    if (!detail.isPending) {
      _draftFor = null;
      state = state.copyWith(alreadyReviewed: true, selectedId: null, detail: null, universityChoice: null, documentNumber: '', studentNumber: '');
      return _reload();
    }
    if (_draftFor != id) {
      // 다른 건으로 옮겼다 — 입력 칸은 이 건의 글자 인식 값으로 새로 채우고 앞 건의 번호 · 학번 · 고른 학교는 버린다.
      _draftFor = id;
      state = state.copyWith(
        detail: AsyncData<GraduateDetail>(detail),
        universityChoice: null,
        documentNumber: detail.ocr?.documentNumber ?? '',
        studentNumber: '',
      );
      return;
    }
    state = state.copyWith(detail: AsyncData<GraduateDetail>(detail));
  }

  Future<bool> _review(ReviewAction action, Future<void> Function(String id) send) async {
    final id = state.selectedId;
    if (id == null || !state.canReview) return false;
    state = state.copyWith(busy: action, error: null);
    try {
      await send(id);
    } on AlreadyReviewed {
      if (!ref.mounted) return false;
      _draftFor = null;
      state = state.copyWith(busy: null, alreadyReviewed: true, universityChoice: null, documentNumber: '', studentNumber: '');
      await _reload();
      return false;
    } on AdminApiFailure catch (failure) {
      if (!ref.mounted) return false;
      // 입력은 그대로 둔다 — 번호 · 학번을 고쳐 다시 낼 수 있게. 문구에는 입력값을 싣지 않는다.
      state = state.copyWith(busy: null, error: _errorText(failure));
      _regateIf(failure);
      return false;
    }
    if (!ref.mounted) return true;
    // 결정이 끝났다 — 평문 입력을 비운다.
    _draftFor = null;
    final items = state.items.value;
    final rest = [for (final item in items ?? const <GraduateItem>[]) if (item.id != id) item];
    if (state.selectedId != id) {
      state = state.copyWith(busy: null, items: items == null ? null : AsyncData(rest), documentNumber: '', studentNumber: '');
      return true;
    }
    // 처리한 줄 자리에 올라온 줄, 맨 아래였으면 맨 위(가장 오래 기다린 건)
    final index = items?.indexWhere((i) => i.id == id) ?? -1;
    final next = rest.isEmpty ? null : rest[index >= 0 && index < rest.length ? index : 0];
    state = state.copyWith(
      items: AsyncData(rest),
      busy: null,
      selectedId: next?.id,
      detail: null,
      universityChoice: null,
      documentNumber: '',
      studentNumber: '',
    );
    if (next != null) unawaited(select(next.id));
    return true;
  }

  static String _errorText(AdminApiFailure failure) {
    if (failure.statusCode == 409) return GraduateConflict.fromCode(failure.reason)?.message ?? reviewFailedText;
    if (failure.statusCode == 422) return invalidInputText;
    return reviewFailedText;
  }

  bool _isLatest(int request) => ref.mounted && request == _listRequest;

  /// 401 · 403 — 세션 만료 · 관리자 해제 · 2단계 풀림. 관문이 다시 판정해 로그인 · 권한 없음 화면으로 보낸다.
  void _regateIf(AdminApiFailure failure) {
    if (failure.isGateProblem) ref.read(gateProvider.notifier).retry();
  }
}
