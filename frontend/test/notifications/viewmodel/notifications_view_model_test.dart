import 'dart:async';

import 'package:campus_mate/notifications/model/app_notification.dart';
import 'package:campus_mate/notifications/model/notifications_repository_provider.dart';
import 'package:campus_mate/notifications/viewmodel/notifications_ui_state.dart';
import 'package:campus_mate/notifications/viewmodel/notifications_view_model.dart';
import 'package:campus_mate/notifications/viewmodel/unread_count_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_notifications_repository.dart';

void main() {
  late FakeNotificationsRepository repo;
  late ProviderContainer container;

  NotificationsPage page(List<AppNotification> items, {int unread = 0, String? next}) =>
      NotificationsPage(items: items, unreadCount: unread, nextBefore: next);

  /// 화면이 구독하듯 끝까지 붙들어 둔다(autoDispose 가 중간에 버리지 않게).
  NotificationsUiState state0() => container.read(notificationsViewModelProvider);
  NotificationsViewModel vm0() => container.read(notificationsViewModelProvider.notifier);

  void start(FakeNotificationsRepository fake) {
    repo = fake;
    container = ProviderContainer(overrides: [notificationsRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);
    container.listen(notificationsViewModelProvider, (_, _) {});
  }

  group('처음 읽기', () {
    test('읽는 동안은 loading, 줄이 있으면 list 이고 안 읽은 수를 종 배지 provider 에 싣는다', () async {
      start(FakeNotificationsRepository(pages: [
        page([fakeNotification('a'), fakeNotification('b', read: true)], unread: 3),
      ]));
      expect(state0().phase, NotificationsPhase.loading);

      await pumpEventQueue();

      expect(state0().phase, NotificationsPhase.list);
      expect(state0().items.map((n) => n.id), ['a', 'b']);
      expect(container.read(unreadCountProvider), 3);
    });

    test('줄이 하나도 없으면 empty', () async {
      start(FakeNotificationsRepository(pages: [page([])]));

      await pumpEventQueue();

      expect(state0().phase, NotificationsPhase.empty);
    });

    test('실패하면 failed 이고, 다시 시도하면 loading 을 거쳐 list 가 된다', () async {
      start(FakeNotificationsRepository(pages: [page([fakeNotification('a')], unread: 1)])..failList = true);
      await pumpEventQueue();
      expect(state0().phase, NotificationsPhase.failed);

      repo.failList = false;
      final retry = vm0().retry();
      expect(state0().phase, NotificationsPhase.loading);
      await retry;

      expect(state0().phase, NotificationsPhase.list);
    });
  });

  group('이어 읽기', () {
    test('next_before 가 있으면 loadMore 가 그 값으로 다음 쪽을 붙인다', () async {
      start(FakeNotificationsRepository(pages: [
        page([fakeNotification('a')], unread: 2, next: 'T1'),
        page([fakeNotification('b')], unread: 2),
      ]));
      await pumpEventQueue();

      await vm0().loadMore();

      expect(repo.listBefores, [null, 'T1']);
      expect(state0().items.map((n) => n.id), ['a', 'b']);
      expect(state0().nextBefore, isNull);
    });

    test('next_before 가 없으면 더 읽지 않는다', () async {
      start(FakeNotificationsRepository(pages: [page([fakeNotification('a')])]));
      await pumpEventQueue();

      await vm0().loadMore();

      expect(repo.listBefores, [null]);
    });

    test('이어 읽는 중에 또 부르면 한 번만 읽는다', () async {
      start(FakeNotificationsRepository(pages: [
        page([fakeNotification('a')], next: 'T1'),
        page([fakeNotification('b')]),
      ]));
      await pumpEventQueue();
      repo.holdList = Completer<void>();

      final first = vm0().loadMore();
      final second = vm0().loadMore();
      expect(state0().isLoadingMore, isTrue);
      repo.holdList!.complete();
      await Future.wait([first, second]);

      expect(repo.listBefores, [null, 'T1']);
    });

    test('이어 읽기가 실패하면 줄은 그대로 두고 다시 읽을 수 있다', () async {
      start(FakeNotificationsRepository(pages: [
        page([fakeNotification('a')], next: 'T1'),
        page([fakeNotification('b')]),
      ]));
      await pumpEventQueue();
      repo.failList = true;
      await vm0().loadMore();

      expect(state0().phase, NotificationsPhase.list);
      expect(state0().items.map((n) => n.id), ['a']);
      expect(state0().isLoadingMore, isFalse);

      repo.failList = false;
      await vm0().loadMore();

      expect(state0().items.map((n) => n.id), ['a', 'b']);
    });

    test('이어 읽는 중 당겨서 새로고침이 실패해도 스피너(isLoadingMore)가 계속 돌지 않는다', () async {
      start(FakeNotificationsRepository(pages: [
        page([fakeNotification('a')], next: 'T1'),
        page([fakeNotification('b')]),
      ]));
      await pumpEventQueue();
      repo.holdList = Completer<void>();

      final more = vm0().loadMore();
      final refreshing = vm0().refresh();
      expect(state0().isLoadingMore, isTrue);
      repo.failList = true;
      repo.holdList!.complete();
      await Future.wait([more, refreshing]);

      expect(state0().isLoadingMore, isFalse);
      expect(state0().items.map((n) => n.id), ['a']);
    });

    test('같은 id 가 겹쳐 오면 한 번만 둔다', () async {
      start(FakeNotificationsRepository(pages: [
        page([fakeNotification('a')], next: 'T1'),
        page([fakeNotification('a'), fakeNotification('b')]),
      ]));
      await pumpEventQueue();

      await vm0().loadMore();

      expect(state0().items.map((n) => n.id), ['a', 'b']);
    });
  });

  group('당겨서 새로고침', () {
    test('첫 쪽을 다시 읽어 줄을 바꾼다', () async {
      start(FakeNotificationsRepository(pages: [page([fakeNotification('a')], unread: 1)]));
      await pumpEventQueue();
      repo.pages = [page([fakeNotification('z'), fakeNotification('a')], unread: 2)];

      await vm0().refresh();

      expect(state0().items.map((n) => n.id), ['z', 'a']);
      expect(container.read(unreadCountProvider), 2);
    });

    test('실패해도 보이던 줄은 그대로 둔다', () async {
      start(FakeNotificationsRepository(pages: [page([fakeNotification('a')])]));
      await pumpEventQueue();
      repo.failList = true;

      await vm0().refresh();

      expect(state0().phase, NotificationsPhase.list);
      expect(state0().items.map((n) => n.id), ['a']);
    });
  });

  group('읽음 처리', () {
    test('markRead 는 그 줄을 바로 읽음으로 바꾸고 안 읽은 수를 하나 줄이고 서버에 알린다', () async {
      start(FakeNotificationsRepository(pages: [
        page([fakeNotification('a'), fakeNotification('b')], unread: 2),
      ]));
      await pumpEventQueue();

      final done = vm0().markRead('a');

      expect(state0().items.first.read, isTrue); // 서버 응답 전에 이미 바뀐다(낙관적)
      expect(container.read(unreadCountProvider), 1);
      await done;
      expect(repo.markedRead, ['a']);
    });

    test('이미 읽은 줄은 서버에 또 알리지 않고 수도 줄이지 않는다', () async {
      start(FakeNotificationsRepository(pages: [page([fakeNotification('a', read: true)], unread: 0)]));
      await pumpEventQueue();

      await vm0().markRead('a');

      expect(repo.markedRead, isEmpty);
      expect(container.read(unreadCountProvider), 0);
    });

    test('서버가 실패해도 조용히 무시한다(줄은 읽음 그대로)', () async {
      start(FakeNotificationsRepository(pages: [page([fakeNotification('a')], unread: 1)])..failRead = true);
      await pumpEventQueue();

      await vm0().markRead('a');

      expect(state0().items.single.read, isTrue);
      expect(state0().phase, NotificationsPhase.list);
    });

    test('안 읽은 수는 0 아래로 내려가지 않는다', () async {
      start(FakeNotificationsRepository(pages: [page([fakeNotification('a')], unread: 0)]));
      await pumpEventQueue();

      await vm0().markRead('a');

      expect(container.read(unreadCountProvider), 0);
    });

    test('markAllRead 는 모든 줄을 읽음으로 바꾸고 수를 0 으로 하고 서버에 알린다', () async {
      start(FakeNotificationsRepository(pages: [
        page([fakeNotification('a'), fakeNotification('b'), fakeNotification('c', read: true)], unread: 2),
      ]));
      await pumpEventQueue();

      final done = vm0().markAllRead();

      expect(state0().items.every((n) => n.read), isTrue);
      expect(container.read(unreadCountProvider), 0);
      await done;
      expect(repo.readAllCount, 1);
    });

    test('markAllRead 가 실패하면 줄과 수를 되돌린다', () async {
      start(FakeNotificationsRepository(pages: [
        page([fakeNotification('a'), fakeNotification('b')], unread: 2),
      ])..failRead = true);
      await pumpEventQueue();

      await vm0().markAllRead();

      expect(state0().items.where((n) => !n.read), hasLength(2));
      expect(container.read(unreadCountProvider), 2);
    });
  });

  group('종 배지 안 읽은 수', () {
    test('refresh 가 서버 값을 읽어 싣는다', () async {
      start(FakeNotificationsRepository(unreadCount: 5));

      await container.read(unreadCountProvider.notifier).refresh();

      expect(container.read(unreadCountProvider), 5);
    });

    test('못 읽으면 앞의 값을 그대로 둔다', () async {
      start(FakeNotificationsRepository(unreadCount: 5));
      await pumpEventQueue(); // 알림함 뷰모델의 첫 읽기가 먼저 끝나게 한다
      await container.read(unreadCountProvider.notifier).refresh();
      repo.failCount = true;
      repo.unreadCount = 9;

      await container.read(unreadCountProvider.notifier).refresh();

      expect(container.read(unreadCountProvider), 5);
    });

    test('읽음 알림이 아직 서버에 닿기 전이면 그 요청이 끝난 뒤에 읽는다(배지가 되살아나지 않게)', () async {
      start(FakeNotificationsRepository(pages: [page([fakeNotification('a')], unread: 1)], unreadCount: 1));
      await pumpEventQueue();
      repo.holdRead = Completer<void>();

      final marking = vm0().markRead('a');
      final counting = container.read(unreadCountProvider.notifier).refresh();
      await pumpEventQueue();
      expect(repo.countCalls, 0); // 읽음 요청이 끝나기를 기다리는 중
      repo.holdRead!.complete();
      await Future.wait([marking, counting]);

      expect(repo.countCalls, 1);
      expect(container.read(unreadCountProvider), 0); // 서버는 이미 0
    });
  });
}
