import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/community/model/data/feed_page.dart';
import 'package:campus_mate/community/model/repository/community_repository_provider.dart';
import 'package:campus_mate/community/viewmodel/notice_list_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/repository/fake_community_repository.dart';

void main() {
  late FakeCommunityRepository repository;

  ProviderContainer container() {
    final container = ProviderContainer(overrides: [communityRepositoryProvider.overrideWithValue(repository)]);
    addTearDown(container.dispose);
    return container;
  }

  Future<ProviderContainer> start() async {
    final c = container();
    c.read(noticeListViewModelProvider);
    await c.read(noticeListViewModelProvider.notifier).refresh();
    return c;
  }

  setUp(() => repository = FakeCommunityRepository());

  test('열면 첫 쪽을 읽고, 맨 위 공지가 띠에 쓸 최신 공지다', () async {
    repository.noticePage = Success(FeedPage(
      items: [noticeFixture(id: 'n2', isNew: true), noticeFixture(id: 'n1')],
      hasMore: true,
    ));

    final c = await start();
    final state = c.read(noticeListViewModelProvider);

    expect(state.isLoading, isFalse);
    expect(state.items.map((notice) => notice.id), ['n2', 'n1']);
    expect(state.hasMore, isTrue);
    expect(state.latest!.id, 'n2');
    expect(state.latest!.isNew, isTrue);
    // build 의 첫 읽기와 refresh 가 겹쳐도 한 번만 간다.
    expect(repository.noticeRequests, hasLength(1));
  });

  test('공지가 없으면 띠에 쓸 공지도 없다', () async {
    final c = await start();

    expect(c.read(noticeListViewModelProvider).items, isEmpty);
    expect(c.read(noticeListViewModelProvider).latest, isNull);
  });

  test('첫 쪽을 못 읽으면 이유를 담고 목록은 비어 있다(띠 없음)', () async {
    repository.noticePage = const FailureResult(NetworkFailure());

    final c = await start();
    final state = c.read(noticeListViewModelProvider);

    expect(state.isLoading, isFalse);
    expect(state.error, isA<NetworkFailure>());
    expect(state.latest, isNull);
  });

  test('다시 읽기가 실패해도 이미 보이는 공지는 그대로 두고 오류를 띄우지 않는다', () async {
    repository.noticePage = Success(FeedPage(items: [noticeFixture()], hasMore: false));
    final c = await start();
    repository.noticePage = const FailureResult(NetworkFailure());

    await c.read(noticeListViewModelProvider.notifier).refresh();
    final state = c.read(noticeListViewModelProvider);

    expect(state.items.single.id, 'n1');
    expect(state.error, isNull);
  });

  test('실패 뒤 다시 읽기에 성공하면 오류가 지워진다', () async {
    repository.noticePage = const FailureResult(NetworkFailure());
    final c = await start();
    repository.noticePage = Success(FeedPage(items: [noticeFixture()], hasMore: false));

    await c.read(noticeListViewModelProvider.notifier).refresh();

    expect(c.read(noticeListViewModelProvider).error, isNull);
    expect(c.read(noticeListViewModelProvider).items, hasLength(1));
  });

  test('더 받기는 맨 아래 공지의 시각 · id 를 커서로 보내고, 겹친 공지는 한 번만 둔다', () async {
    final bottom = noticeFixture(id: 'n2', createdAt: DateTime(2026, 11, 20, 9));
    repository.noticePage = Success(FeedPage(items: [noticeFixture(id: 'n3'), bottom], hasMore: true));
    final c = await start();
    repository.nextNoticePage = Success(FeedPage(items: [bottom, noticeFixture(id: 'n1')], hasMore: false));

    await c.read(noticeListViewModelProvider.notifier).loadMore();
    final state = c.read(noticeListViewModelProvider);

    expect(repository.noticeRequests.last, (before: bottom.createdAt, beforeId: 'n2'));
    expect(state.items.map((notice) => notice.id), ['n3', 'n2', 'n1']);
    expect(state.hasMore, isFalse);
    expect(state.isLoadingMore, isFalse);
  });

  test('더 없음이면 더 받기를 부르지 않는다', () async {
    repository.noticePage = Success(FeedPage(items: [noticeFixture()], hasMore: false));
    final c = await start();

    await c.read(noticeListViewModelProvider.notifier).loadMore();

    expect(repository.noticeRequests, hasLength(1));
  });

  test('더 받는 중에 또 불려도 한 번만 간다', () async {
    repository.noticePage = Success(FeedPage(items: [noticeFixture()], hasMore: true));
    final c = await start();
    final hold = repository.holdNotices = Completer<void>();
    final viewModel = c.read(noticeListViewModelProvider.notifier);

    final first = viewModel.loadMore();
    final second = viewModel.loadMore();
    expect(c.read(noticeListViewModelProvider).isLoadingMore, isTrue);
    hold.complete();
    await (first, second).wait;

    expect(repository.noticeRequests, hasLength(2));
  });

  test('더 받기가 실패하면 조용히 멈추고 목록은 그대로다', () async {
    repository.noticePage = Success(FeedPage(items: [noticeFixture()], hasMore: true));
    final c = await start();
    repository.nextNoticePage = const FailureResult(NetworkFailure());

    await c.read(noticeListViewModelProvider.notifier).loadMore();
    final state = c.read(noticeListViewModelProvider);

    expect(state.isLoadingMore, isFalse);
    expect(state.items, hasLength(1));
    expect(state.error, isNull);
  });

  test('상세에서 댓글 수가 바뀌면 그 공지 줄의 숫자를 맞춘다', () async {
    repository.noticePage = Success(FeedPage(items: [noticeFixture(), noticeFixture(id: 'n2')], hasMore: false));
    final c = await start();

    c.read(noticeListViewModelProvider.notifier).updateCommentCount('n1', 4);

    expect(c.read(noticeListViewModelProvider).items.first.commentCount, 4);
    expect(c.read(noticeListViewModelProvider).items.last.commentCount, 0);
  });

  test('받는 사이 버려져도(로그아웃) 늦은 응답이 던지지 않는다', () async {
    final hold = repository.holdNotices = Completer<void>();
    final c = ProviderContainer(overrides: [communityRepositoryProvider.overrideWithValue(repository)]);
    c.read(noticeListViewModelProvider);
    await Future<void>.delayed(Duration.zero);
    expect(repository.noticeRequests, hasLength(1));

    c.dispose();
    hold.complete();
    await Future<void>.delayed(Duration.zero);
  });
}
