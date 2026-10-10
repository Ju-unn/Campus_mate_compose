import 'dart:async';

import 'package:campus_mate/notifications/model/notifications_repository_provider.dart';
import 'package:campus_mate/notifications/viewmodel/notifications_ui_state.dart';
import 'package:campus_mate/notifications/viewmodel/unread_count_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 09c 알림함. 들어올 때마다 새로 읽는다(autoDispose).
final notificationsViewModelProvider =
    NotifierProvider.autoDispose<NotificationsViewModel, NotificationsUiState>(NotificationsViewModel.new);

class NotificationsViewModel extends Notifier<NotificationsUiState> {
  static const _pageSize = 30;

  /// 당겨서 새로고침이 끝나기 전에 도착한 옛 "이어 읽기" 결과를 버리기 위한 번호.
  int _epoch = 0;

  /// 가장 나중에 시작한 "이어 읽기" 번호. 옛 이어 읽기가 버려질 때 더 새 이어 읽기가 돌고 있으면 그 스피너는 건드리지 않는다.
  int _moreToken = 0;

  @override
  NotificationsUiState build() {
    Future.microtask(load);
    return const NotificationsUiState();
  }

  /// 처음 읽기. 로딩 모습을 거친다.
  Future<void> load() async {
    state = const NotificationsUiState();
    await _loadFirstPage(keepOnFailure: false);
  }

  /// 실패 화면의 "다시 시도".
  Future<void> retry() => load();

  /// 당겨서 새로고침. 보이던 줄은 그대로 둔 채 읽고, 실패해도 조용히 둔다.
  Future<void> refresh() => _loadFirstPage(keepOnFailure: true);

  Future<void> _loadFirstPage({required bool keepOnFailure}) async {
    final epoch = ++_epoch;
    final result = await ref.read(notificationsRepositoryProvider).fetchPage(limit: _pageSize);
    if (!ref.mounted || epoch != _epoch) return;
    result.when(
      onSuccess: (page) {
        ref.read(unreadCountProvider.notifier).set(page.unreadCount);
        state = NotificationsUiState(
          phase: page.items.isEmpty ? NotificationsPhase.empty : NotificationsPhase.list,
          items: page.items,
          nextBefore: page.nextBefore,
        );
      },
      onFailure: (_) {
        if (keepOnFailure && state.items.isNotEmpty) return;
        state = const NotificationsUiState(phase: NotificationsPhase.failed);
      },
    );
  }

  /// 목록 끝에 닿으면 다음 쪽을 붙인다. 실패하면 줄은 그대로 두고, 다시 끝에 닿을 때 또 읽는다.
  Future<void> loadMore() async {
    final before = state.nextBefore;
    if (before == null || state.isLoadingMore || state.phase != NotificationsPhase.list) return;
    final epoch = _epoch;
    final token = ++_moreToken;
    state = state.copyWith(isLoadingMore: true);
    final result = await ref.read(notificationsRepositoryProvider).fetchPage(limit: _pageSize, before: before);
    if (!ref.mounted) return;
    if (epoch != _epoch) {
      // 새로고침이 앞질렀다 — 이 결과는 버린다. 새로고침이 실패해 줄을 그대로 둔 경우 스피너가 남지 않게 끈다.
      if (token == _moreToken) state = state.copyWith(isLoadingMore: false);
      return;
    }
    result.when(
      onSuccess: (page) {
        final known = {for (final item in state.items) item.id};
        state = NotificationsUiState(
          phase: NotificationsPhase.list,
          items: [...state.items, for (final item in page.items) if (!known.contains(item.id)) item],
          nextBefore: page.nextBefore,
        );
      },
      onFailure: (_) => state = state.copyWith(isLoadingMore: false),
    );
  }

  /// 한 줄을 읽음으로. 화면 · 배지는 바로 바꾸고, 서버 실패는 조용히 무시한다(다음에 읽을 때 서버 값으로 맞춰진다).
  Future<void> markRead(String id) {
    final index = state.items.indexWhere((item) => item.id == id);
    if (index < 0 || state.items[index].read) return Future.value();
    state = state.copyWith(items: [
      for (final item in state.items) item.id == id ? item.asRead() : item,
    ]);
    final unread = ref.read(unreadCountProvider.notifier)..decrement();
    final request = ref.read(notificationsRepositoryProvider).markRead(id).then<void>((_) {});
    unread.track(request);
    return request;
  }

  /// "모두 읽음". 바로 바꾸고, 서버가 안 받으면 되돌린다(눌러서 한 일이라 조용히 넘기지 않는다).
  Future<void> markAllRead() async {
    final before = state.items;
    final unread = ref.read(unreadCountProvider.notifier);
    final countBefore = ref.read(unreadCountProvider);
    state = state.copyWith(items: [for (final item in before) item.asRead()]);
    unread.set(0);
    final request = ref.read(notificationsRepositoryProvider).markAllRead();
    unread.track(request.then<void>((_) {}));
    final result = await request;
    if (!ref.mounted) return;
    result.when(
      onSuccess: (_) {},
      onFailure: (_) {
        state = state.copyWith(items: before);
        unread.set(countBefore);
      },
    );
  }
}
