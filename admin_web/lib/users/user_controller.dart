import 'dart:async';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/gate/gate_controller.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:campus_mate_admin/reports/report_controller.dart' show ActionResult;
import 'package:campus_mate_admin/reports/report_item.dart' show ProfileAction;
import 'package:campus_mate_admin/users/user_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum UserSearchMode { nickname, schoolMail }

/// A5 찾기 상태. **학교 메일은 어디에도 들고 있지 않는다** — 칸 글자는 화면의 입력 칸에만 있고, 여기는 어떤 방식으로
/// 찾았는지(칩)와 찾은 줄들뿐이다(대장 결정 2 · 설계 §14-3).
class UserSearchState {
  const UserSearchState({this.mode = UserSearchMode.nickname, this.resultMode = UserSearchMode.nickname, this.results = const AsyncLoading()});

  /// 고른 칩
  final UserSearchMode mode;

  /// 지금 보이는 결과를 만든 찾기 방식(결과 없음 문구가 다르다)
  final UserSearchMode resultMode;
  final AsyncValue<List<UserSummary>> results;

  UserSearchState copyWith({UserSearchMode? mode, UserSearchMode? resultMode, AsyncValue<List<UserSummary>>? results}) {
    return UserSearchState(mode: mode ?? this.mode, resultMode: resultMode ?? this.resultMode, results: results ?? this.results);
  }
}

/// 화면에 들어올 때마다 가입 최근 순으로 새로 받고(비운 칸으로 찾는 것과 같다), 칩 · 검색은 이 안에서 바꾼다.
/// 화면을 떠나면 모두 버린다(찾은 줄도 남기지 않는다).
final userSearchProvider = NotifierProvider.autoDispose<UserSearchController, UserSearchState>(UserSearchController.new);

class UserSearchController extends Notifier<UserSearchState> {
  late AdminApi _api;

  /// 늦게 온 응답(칩을 바꾼 뒤)을 버리려고 요청마다 올린다
  int _request = 0;

  @override
  UserSearchState build() {
    _api = ref.watch(adminApiProvider);
    unawaited(_run(UserSearchMode.nickname, _api.listUsers, announce: false)); // 처음 상태가 이미 받는 중
    return const UserSearchState();
  }

  /// 칩 바꾸기. 결과는 그대로 두고 방식만 바뀐다.
  void setMode(UserSearchMode mode) => state = state.copyWith(mode: mode);

  /// 지금 칩의 방식으로 찾는다. [text] 는 이 호출 안에서만 쓰고 어디에도 두지 않는다. 끝나면(성공 · 못 찾음 · 오류 모두) 돌아온다 —
  /// 학교 메일 칸을 비우는 일은 이 Future 가 끝난 뒤 화면이 한다.
  Future<void> search(String text) {
    final query = text.trim();
    if (state.mode == UserSearchMode.nickname) return _run(UserSearchMode.nickname, () => _api.listUsers(q: query));
    if (query.isEmpty) return Future.value();
    return _run(UserSearchMode.schoolMail, () => _api.searchUsersBySchoolEmail(query));
  }

  /// 오류 화면의 "다시 시도" — 가입 최근 순으로
  void reload() => unawaited(_run(UserSearchMode.nickname, _api.listUsers));

  Future<void> _run(UserSearchMode mode, Future<List<UserSummary>> Function() load, {bool announce = true}) async {
    final request = ++_request;
    if (announce) state = state.copyWith(resultMode: mode, results: const AsyncLoading());
    final List<UserSummary> found;
    try {
      found = await load();
    } on AdminApiFailure catch (failure) {
      if (!_isLatest(request)) return;
      state = state.copyWith(results: AsyncError(failure, StackTrace.current));
      if (failure.isGateProblem) ref.read(gateProvider.notifier).retry();
      return;
    }
    if (_isLatest(request)) state = state.copyWith(results: AsyncData(found));
  }

  bool _isLatest(int request) => ref.mounted && request == _request;
}

/// A5 상세 한 명(주소 `/users/{id}` 마다 하나). 조치는 여기서 보내고 성공 · 409 뒤 상세를 새로 받는다.
/// 열람 결과(전화 · 카톡)는 **여기 두지 않는다** — [viewPrivate] 가 돌려주기만 하고 대화상자가 들고 있다가 닫으면 버린다.
final userDetailProvider = NotifierProvider.autoDispose.family<UserDetailController, AsyncValue<UserDetail>, String>(
  UserDetailController.new,
);

class UserDetailController extends Notifier<AsyncValue<UserDetail>> {
  UserDetailController(this.id);

  final String id;
  late AdminApi _api;
  int _request = 0;

  @override
  AsyncValue<UserDetail> build() {
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

  Future<ActionResult> adjustHearts(int amount, String reason) => _act(() => _api.adjustHearts(id, amount, reason));

  Future<ActionResult> addNote(String text) => _act(() => _api.addUserNote(id, text));

  /// 정지 · 정지 해제(D2 경로 — 사람 번호가 곧 프로필 번호다)
  Future<ActionResult> actOnProfile(ProfileAction action, String reason) => _act(() => _api.actOnProfile(id, action, reason));

  /// 전화 · 카톡 열람 — 받은 값은 돌려주기만 한다(탈퇴 계정 409 는 [ActionResult.withdrawn])
  Future<(ActionResult, PrivateContact?)> viewPrivate(String reason) async {
    try {
      return (ActionResult.done, await _api.viewPrivate(id, reason));
    } on AdminApiFailure catch (failure) {
      _regateIf(failure);
      return (failure.statusCode == 409 && failure.reason == 'account_withdrawn' ? ActionResult.withdrawn : ActionResult.failed, null);
    }
  }

  /// 탈퇴 대행. 성공이면 바깥 정리 결과를 함께 준다. 성공 뒤 상세를 새로 받는다(탈퇴한 계정 표시).
  Future<(ActionResult, CloseAccountResult?)> closeAccount({required String reason, required String verifiedBy}) async {
    final CloseAccountResult closed;
    try {
      closed = await _api.closeAccount(id, reason: reason, verifiedBy: verifiedBy);
    } on AlreadyReviewed {
      if (ref.mounted) unawaited(refresh());
      return (ActionResult.alreadyDone, null);
    } on AdminApiFailure catch (failure) {
      _regateIf(failure);
      if (failure.statusCode == 409 && failure.reason == 'account_withdrawn') {
        if (ref.mounted) unawaited(refresh());
        return (ActionResult.withdrawn, null);
      }
      return (ActionResult.failed, null);
    }
    if (ref.mounted) unawaited(refresh());
    return (ActionResult.done, closed);
  }

  Future<ActionResult> _act(Future<void> Function() send) async {
    try {
      await send();
    } on AlreadyReviewed {
      if (ref.mounted) unawaited(refresh());
      return ActionResult.alreadyDone;
    } on AdminApiFailure catch (failure) {
      _regateIf(failure);
      if (failure.statusCode == 409 && failure.reason == 'insufficient_hearts') return ActionResult.insufficientHearts;
      if (failure.statusCode == 409 && failure.reason == 'account_withdrawn') {
        if (ref.mounted) unawaited(refresh());
        return ActionResult.withdrawn;
      }
      return ActionResult.failed;
    }
    if (ref.mounted) unawaited(refresh());
    return ActionResult.done;
  }

  Future<void> _load() async {
    final request = ++_request;
    final UserDetail detail;
    try {
      detail = await _api.getUser(id);
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
