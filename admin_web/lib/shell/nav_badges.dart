import 'dart:async';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/gate/gate_controller.dart';
import 'package:campus_mate_admin/gate/gate_stage.dart';
import 'package:campus_mate_admin/platform/confirm_store.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:campus_mate_admin/server_status/server_status_models.dart';
import 'package:campus_mate_admin/shell/admin_section.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 왼쪽 메뉴 빨간 숫자(설계 2026-11-17-admin-server-status). 시계 · 주기 호출은 없다 — 서버 숫자는 셸이 처음 뜰 때 한 번과
/// [새로고침] 때만, 대기 건수는 그때와 메뉴 이동 때만 읽는다. 셸 배지와 서버 상태 화면이 같은 값을 쓰도록 둘 다 keepAlive.

/// 지금 들어온 관리자(메일), 관문 단계가 Ready 가 아니면 null. 아래 세 provider 가 이것을 지켜봐 로그아웃 · 다른 관리자 로그인 때
/// 처음부터 다시 만든다 — 같은 브라우저로 들어온 다음 사람이 앞 사람의 숫자를 보지 않게(대장 11-18). 셸의 로그아웃 단추뿐 아니라
/// 세션이 끊겨 관문이 로그아웃시킨 때도 같이 비워진다. 관문 재판정 중에는 앞 단계를 그대로 들고 있어 다시 읽지 않는다.
String? _signedInAdmin(Ref ref) => ref.watch(gateProvider.select((gate) => switch (gate.value) { Ready(:final email) => email, _ => null }));

/// 시험은 메모리 칸 · 던지는 칸으로 갈아 끼운다.
final confirmStoreProvider = Provider<ConfirmStore>((ref) => ConfirmStore());

/// 서버 상태 한 벌. 새로고침 중([loading])에도 앞 숫자([status])를 그대로 두어 화면이 깜빡이지 않게 한다 —
/// AsyncValue 의 "앞 값을 든 로딩"은 Riverpod 3 에서 밖에 열려 있지 않아 따로 둔다.
class ServerStatusState {
  const ServerStatusState({this.status, this.failure, this.loading = false});

  final ServerStatus? status;
  final AdminApiFailure? failure;
  final bool loading;
}

final serverStatusProvider = NotifierProvider<ServerStatusController, ServerStatusState>(ServerStatusController.new);

class ServerStatusController extends Notifier<ServerStatusState> {
  int _request = 0;

  @override
  ServerStatusState build() {
    if (_signedInAdmin(ref) == null) return const ServerStatusState();
    unawaited(_load(ref.watch(adminApiProvider)));
    return const ServerStatusState(loading: true);
  }

  /// 도는 중이면 무시한다(두 번 눌러도 한 번만 부른다). 실패 뒤 [다시 시도]도 이것.
  void refresh() {
    if (state.loading) return;
    state = ServerStatusState(status: state.status, loading: true);
    unawaited(_load(ref.read(adminApiProvider)));
  }

  Future<void> _load(AdminApi api) async {
    final request = ++_request;
    try {
      final status = await api.serverStatus();
      if (ref.mounted && request == _request) state = ServerStatusState(status: status);
    } on AdminApiFailure catch (failure) {
      if (!ref.mounted || request != _request) return;
      state = ServerStatusState(failure: failure);
      if (failure.isGateProblem) ref.read(gateProvider.notifier).retry();
    }
  }
}

/// 인증샷 검수 · 졸업생 · 신고 · 문의 대기 건수. 다시 읽는 동안에는 앞 숫자를 그대로 둔다. 실패면 배지만 숨긴다(관문은 화면이 맡는다).
final pendingCountsProvider = NotifierProvider<PendingCountsController, AsyncValue<PendingCounts>>(PendingCountsController.new);

class PendingCountsController extends Notifier<AsyncValue<PendingCounts>> {
  int _request = 0;

  @override
  AsyncValue<PendingCounts> build() {
    if (_signedInAdmin(ref) == null) return const AsyncLoading();
    unawaited(_load(ref.watch(adminApiProvider)));
    return const AsyncLoading();
  }

  void refresh() {
    if (_signedInAdmin(ref) != null) unawaited(_load(ref.read(adminApiProvider)));
  }

  Future<void> _load(AdminApi api) async {
    final request = ++_request;
    try {
      final counts = await api.pendingCounts();
      if (ref.mounted && request == _request) state = AsyncData(counts);
    } on AdminApiFailure catch (failure) {
      if (ref.mounted && request == _request) state = AsyncError(failure, StackTrace.current);
    }
  }
}

/// [확인]으로 본 이상의 열쇠(대장 결정 11-18 (가)). 이상 시각은 5분 칸의 시작이라 "확인 시각 뒤" 로 세면 아직 진행 중인 칸에
/// 나중에 생긴 이상을 놓친다 — 그래서 시각이 아니라 줄마다 열쇠로 본다. 배지 · 흐리게 표시가 같은 기준을 쓴다.
final serverSeenProvider = NotifierProvider<ServerSeenController, Set<String>>(ServerSeenController.new);

class ServerSeenController extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    _signedInAdmin(ref);
    return ref.watch(confirmStoreProvider).read();
  }

  /// 지금 목록의 이상을 모두 본 것으로 둔다. 지금 응답 창(첫 칸 시작) 밖 열쇠 · 시각을 못 읽는 열쇠는 버려 저장 값이 자라지 않게 한다.
  void confirm(ServerStatus status) {
    final windowStart = status.buckets.isEmpty ? status.checkedAt.subtract(statusWindow) : status.buckets.first.start;
    final next = {
      for (final key in state)
        if (_timeOf(key) case final at? when !at.isBefore(windowStart)) key,
      for (final anomaly in status.anomalies) anomalyKey(anomaly),
    };
    ref.read(confirmStoreProvider).write(next);
    state = next;
  }

  static DateTime? _timeOf(String key) {
    final split = key.lastIndexOf('|');
    return split < 0 ? null : DateTime.tryParse(key.substring(0, split));
  }
}

/// 서버 응답 창(backend monitoring.py WINDOW_MINUTES) — 칸이 하나도 없을 때만 쓴다
const Duration statusWindow = Duration(minutes: 180);

/// 이상 한 줄의 열쇠 "시각 UTC ISO|종류"
String anomalyKey(StatusAnomaly anomaly) => '${anomaly.at.toUtc().toIso8601String()}|${anomaly.kind.name}';

/// 아직 안 본 이상 줄 수. 못 읽었거나 읽는 중이면 0.
int newAnomalyCount(ServerStatus? status, Set<String> seen) {
  if (status == null) return 0;
  return status.anomalies.where((a) => !seen.contains(anomalyKey(a))).length;
}

/// 메뉴 하나의 숫자. 서버 상태 = 새 이상 수, 대기 건수가 있는 네 메뉴 = 그 건수, 그 밖 0.
int navBadgeCount(AdminSection section, {required int serverNew, required PendingCounts? pending}) {
  return switch (section) {
    AdminSection.serverStatus => serverNew,
    AdminSection.heartTasks => pending?.heartTasks ?? 0,
    AdminSection.graduates => pending?.graduates ?? 0,
    AdminSection.reports => pending?.reports ?? 0,
    AdminSection.inquiries => pending?.inquiries ?? 0,
    _ => 0,
  };
}

/// 셸이 SideNav 에 넘기는 메뉴별 숫자
final navBadgesProvider = Provider<int Function(AdminSection)>((ref) {
  final serverNew = newAnomalyCount(ref.watch(serverStatusProvider).status, ref.watch(serverSeenProvider));
  final pending = ref.watch(pendingCountsProvider).value;
  return (section) => navBadgeCount(section, serverNew: serverNew, pending: pending);
});
